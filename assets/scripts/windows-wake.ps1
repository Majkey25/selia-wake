param(
    [string] $Action = 'Inspect',
    [string] $AdapterId = '',
    [switch] $ElevatedWorker
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$systemDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::System)
$powerCfg = Join-Path $systemDirectory 'powercfg.exe'
$windowsPowerShell = Join-Path $systemDirectory 'WindowsPowerShell\v1.0\powershell.exe'
$nativeEncoding = [Console]::OutputEncoding

function ConvertTo-NativeArgument([string] $Value) {
    if ($Value.Contains([char]0)) { throw 'A native argument contains a null character.' }
    # Windows PowerShell 5.1 has no ProcessStartInfo.ArgumentList.
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-PowerCfg([string[]] $NativeArguments) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $powerCfg
    $start.Arguments = ($NativeArguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $start.WorkingDirectory = $systemDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $nativeEncoding
    $start.StandardErrorEncoding = $nativeEncoding
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'powercfg did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'powercfg timed out after 10 seconds.'
        }
        $output = $stdout.GetAwaiter().GetResult().Trim()
        $errorOutput = $stderr.GetAwaiter().GetResult().Trim()
        if ($process.ExitCode -ne 0) {
            throw "powercfg $($NativeArguments[0]) failed ($($process.ExitCode)): $errorOutput $output"
        }
        return $output
    } finally {
        $process.Dispose()
    }
}

function Get-Broadcast([string] $Address, [int] $PrefixLength) {
    $bytes = [Net.IPAddress]::Parse($Address).GetAddressBytes()
    if ($bytes.Length -ne 4 -or $PrefixLength -lt 0 -or $PrefixLength -gt 32) {
        throw 'Invalid IPv4 address or prefix length.'
    }
    if ($PrefixLength -ge 31) { return '' }
    for ($index = 0; $index -lt 4; $index++) {
        $bits = [Math]::Min(8, [Math]::Max(0, $PrefixLength - 8 * $index))
        $bytes[$index] = $bytes[$index] -bor (255 -shr $bits)
    }
    return $bytes -join '.'
}

function Get-MagicSetting($Adapter) {
    $result = [pscustomobject]@{ Property = $null; Desired = ''; Enabled = $null; Detail = '' }
    try {
        $properties = @(Get-NetAdapterAdvancedProperty -Name ([Management.Automation.WildcardPattern]::Escape($Adapter.Name)) -AllProperties -IncludeHidden)
        $keywords = @('*WakeOnMagicPacket')
        if ($Adapter.DriverProvider -like 'MediaTek*') { $keywords += 'DisableWakeOnMagic' }
        foreach ($keyword in $keywords) {
            $instanceId = ([guid] $Adapter.InterfaceGuid).ToString('B') + '::' + $keyword
            $matchingProperties = @($properties | Where-Object { $_.InstanceID -eq $instanceId -and $_.RegistryKeyword -eq $keyword })
            if ($matchingProperties.Count -ne 1) { continue }
            $result.Property = $matchingProperties[0]
            $result.Desired = if ($keyword -eq '*WakeOnMagicPacket') { '1' } else { '0' }
            $values = @($result.Property.RegistryValue)
            if ($values.Count -eq 1 -and [string] $values[0] -in @('0', '1')) {
                $result.Enabled = [string] $values[0] -eq $result.Desired
                $result.Detail = "$keyword=$($values[0]) is the stored driver setting."
            } else {
                $result.Detail = "$keyword has an unrecognized value."
            }
            return $result
        }
        $result.Detail = 'No recognized Magic Packet property is available; its state is unknown.'
    } catch {
        $result.Detail = "Magic Packet property could not be read: $($_.Exception.Message)"
    }
    return $result
}

function Get-WakeSnapshot {
    $queries = @{}
    $queryErrors = @()
    foreach ($query in @('all_devices', 'wake_programmable', 'wake_armed', 'wake_from_any')) {
        try {
            $queries[$query] = @((Invoke-PowerCfg @('/devicequery', $query)) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        } catch {
            $queries[$query] = $null
            $queryErrors += $_.Exception.Message
        }
    }
    try { $sleepStates = Invoke-PowerCfg @('/a') }
    catch { $sleepStates = "Sleep states unavailable: $($_.Exception.Message)" }
    $devices = @()
    try { $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -OperationTimeoutSec 10) }
    catch { $queryErrors += "Device identity could not be read: $($_.Exception.Message)" }
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.AddressState -eq 'Preferred' -and -not $_.SkipAsSource })
    $entries = @(foreach ($adapter in @(Get-NetAdapter -Physical | Sort-Object InterfaceIndex)) {
        if (-not $adapter.HardwareInterface -or $adapter.Virtual -or $adapter.Status -ne 'Up' -or $adapter.InterfaceType -notin @(6, 71)) { continue }
        $address = @($addresses | Where-Object { $_.InterfaceIndex -eq $adapter.InterfaceIndex } | Sort-Object IPAddress | Select-Object -First 1)
        if ($address.Count -eq 0) { continue }
        $magic = Get-MagicSetting $adapter
        $detail = @($magic.Detail) + $queryErrors
        $deviceName = $null
        $identity = @($devices | Where-Object { $_.DeviceID -eq $adapter.PnPDeviceID })
        if ($identity.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($identity[0].Name)) {
            $name = [string] $identity[0].Name
            $sameName = @($devices | Where-Object { $_.Name -eq $name })
            if ($sameName.Count -eq 1 -and @($queries.all_devices | Where-Object { $_ -eq $name }).Count -eq 1) {
                $deviceName = $name
            }
        }
        $wakeEnabled = $null
        $supportsWake = $null
        $canEnable = $false
        if ($null -ne $deviceName) {
            if ($null -ne $queries.wake_armed) { $wakeEnabled = $queries.wake_armed -contains $deviceName }
            if ($null -ne $queries.wake_from_any) { $supportsWake = $queries.wake_from_any -contains $deviceName }
            $canEnable = $null -ne $queries.wake_programmable -and $queries.wake_programmable -contains $deviceName
        } else {
            $detail += 'The adapter cannot be mapped uniquely to a powercfg device; wake capability and arming are unknown.'
        }
        $detail += 'Windows settings do not verify firmware support or physical wake. Stored driver settings may require an adapter restart to take effect.'
        $report = [ordered]@{
            id = ([guid] $adapter.InterfaceGuid).ToString('D')
            name = [string] $adapter.Name
            description = [string] $adapter.InterfaceDescription
            mac = [string] $adapter.MacAddress
            ip = [string] $address[0].IPAddress
            broadcast = Get-Broadcast $address[0].IPAddress $address[0].PrefixLength
            connection = if ($adapter.InterfaceType -eq 71 -or $adapter.NdisPhysicalMedium -in @(1, 9)) { 'wifi' } else { 'ethernet' }
            wakeEnabled = $wakeEnabled
            magicPacketEnabled = $magic.Enabled
            supportsWake = $supportsWake
            detail = $detail -join ' '
            restartRequired = $false
        }
        [pscustomobject]@{ Adapter = $adapter; Magic = $magic; DeviceName = $deviceName; CanEnable = $canEnable; Report = $report }
    })
    return [pscustomobject]@{
        Entries = $entries
        Report = [ordered]@{
            platform = 'windows'
            machineName = [Environment]::MachineName
            sleepStates = $sleepStates
            adapters = @($entries | ForEach-Object { $_.Report })
        }
    }
}

$report = [ordered]@{ platform = 'windows'; machineName = [Environment]::MachineName; sleepStates = ''; adapters = @() }
$restartRequired = $false
$mutationAttempted = $false
$failed = $false
$sourceLock = $null
try {
    if ($Action -notin @('Inspect', 'Enable')) { throw 'Action must be Inspect or Enable.' }
    $selectedGuid = [guid]::Empty
    if ($AdapterId -ne '' -or $Action -eq 'Enable') {
        if ((-not [guid]::TryParseExact($AdapterId, 'D', [ref] $selectedGuid) -and -not [guid]::TryParseExact($AdapterId, 'B', [ref] $selectedGuid)) -or $selectedGuid -eq [guid]::Empty) {
            throw 'AdapterId must be a nonempty adapter GUID.'
        }
        $AdapterId = $selectedGuid.ToString('D')
    }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($ElevatedWorker -and ($Action -ne 'Enable' -or -not $isAdmin)) { throw 'The elevated worker requires Enable and administrator privileges.' }
    # Hold the reviewed file through UAC and worker completion, including caller cleanup attempts.
    $sourceLock = [IO.File]::Open($PSCommandPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    foreach ($module in @('NetAdapter', 'NetTCPIP', 'CimCmdlets')) {
        Import-Module (Join-Path $systemDirectory "WindowsPowerShell\v1.0\Modules\$module\$module.psd1") -ErrorAction Stop
    }
    $snapshot = Get-WakeSnapshot
    $report = $snapshot.Report
    if ($Action -eq 'Enable') {
        $selected = @($snapshot.Entries | Where-Object { $_.Report.id -eq $AdapterId })
        if ($selected.Count -ne 1) { throw 'The selected GUID is not an active physical IPv4 adapter.' }
        $entry = $selected[0]
        if ($null -eq $entry.Magic.Property) { throw $entry.Magic.Detail }
        if ($null -eq $entry.DeviceName -or ($entry.Report.wakeEnabled -ne $true -and -not $entry.CanEnable)) {
            throw 'Windows does not expose an unambiguous, configurable wake device for this adapter.'
        }
        if ($entry.Report.wakeEnabled -ne $true -or $entry.Magic.Enabled -ne $true) {
            if (-not $isAdmin) {
                $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Action', 'Enable', '-AdapterId', $AdapterId, '-ElevatedWorker')
                $commandLine = ($arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
                try {
                    $worker = Start-Process -FilePath $windowsPowerShell -ArgumentList $commandLine -WorkingDirectory $systemDirectory -Verb RunAs -WindowStyle Hidden -PassThru -Wait
                } catch {
                    throw "Administrator approval was cancelled or elevation failed: $($_.Exception.Message)"
                }
                try {
                    $worker.Refresh()
                    $workerExit = $worker.ExitCode
                } finally {
                    $worker.Dispose()
                }
                # Only the hidden worker uses 3010/3011 to preserve a pending restart across UAC.
                $restartRequired = $workerExit -in @(3010, 3011)
                $mutationAttempted = $true
                $snapshot = Get-WakeSnapshot
                $report = $snapshot.Report
                if ($workerExit -notin @(0, 3010)) {
                    throw "Elevated wake configuration failed (exit $workerExit). Settings may have partially changed; inspect the reported state."
                }
            } else {
                $mutationAttempted = $true
                if ($entry.Report.wakeEnabled -ne $true) { $null = Invoke-PowerCfg @('/deviceenablewake', $entry.DeviceName) }
                if ($entry.Magic.Enabled -ne $true) {
                    Set-NetAdapterAdvancedProperty -InputObject $entry.Magic.Property -RegistryValue $entry.Magic.Desired -NoRestart -Confirm:$false | Out-Null
                    $restartRequired = $true
                }
                $snapshot = Get-WakeSnapshot
                $report = $snapshot.Report
            }
            $fresh = @($snapshot.Entries | Where-Object { $_.Report.id -eq $AdapterId })
            if ($fresh.Count -ne 1 -or $fresh[0].Report.wakeEnabled -ne $true -or $fresh[0].Magic.Enabled -ne $true) {
                throw 'Windows did not confirm both wake arming and the stored Magic Packet setting after the operation.'
            }
        }
    }
} catch {
    $failed = $true
    $message = $_.Exception.Message
    if ($mutationAttempted) {
        try {
            $snapshot = Get-WakeSnapshot
            $report = $snapshot.Report
            $fresh = @($snapshot.Entries | Where-Object { $_.Report.id -eq $AdapterId })
            if ($entry.Magic.Enabled -ne $true -and $fresh.Count -eq 1 -and $fresh[0].Magic.Enabled -eq $true) {
                $restartRequired = $true
            }
        } catch { $message += " Fresh inspection also failed: $($_.Exception.Message)" }
        $message += ' An operation may have changed settings before failing.'
    }
    $report['error'] = $message
} finally {
    if ($null -ne $sourceLock) { $sourceLock.Dispose() }
}

foreach ($adapterReport in $report.adapters) {
    if ($adapterReport.id -eq $AdapterId -and $restartRequired) {
        $adapterReport.restartRequired = $true
        $adapterReport.detail += ' The Magic Packet property changed without restarting the adapter; a restart is required before relying on it.'
    }
}
if ($AdapterId -ne '') { $report.adapters = @($report.adapters | Sort-Object @{ Expression = { $_.id -ne $AdapterId } }) }
if ($ElevatedWorker) {
    if ($failed) {
        if ($restartRequired) { exit 3011 }
        exit 1
    }
    if ($restartRequired) { exit 3010 }
    exit 0
}
$json = ConvertTo-Json -InputObject $report -Depth 5 -Compress
$bytes = [Text.Encoding]::UTF8.GetBytes($json + [Environment]::NewLine)
$output = [Console]::OpenStandardOutput()
$output.Write($bytes, 0, $bytes.Length)
$output.Flush()
if ($failed) { exit 1 }
