# Standalone CLI

The Go CLI in `cli/` uses only the standard library. It needs no Flutter runtime,
cloud service, shell commands, or network discovery. A single executable can act
as a User or a Waker.

Windows amd64, Linux amd64, Linux arm64, Linux ARMv7, and macOS amd64/arm64 are
build targets. ARMv7 means a compatible 32-bit Raspberry Pi OS and CPU. Older
ARMv6 Pi boards are not included. Cross-compilation
does not prove execution on those operating systems or actual hardware wake.

## Build and install

These source-build instructions are for maintainers with prior written
authorization from Majkey25 under [LICENSE](../LICENSE). The source-visible
license does not grant general permission to build the CLI. Users may install
and use unmodified official releases as described in that license.

Authorized maintainers need a current supported Go toolchain, Go 1.25 or newer.
CI uses Go 1.27.3. From `cli/`:

```sh
go test -count=1 ./...
go vet ./...
CGO_ENABLED=0 go build -trimpath -buildvcs=false -ldflags='-s -w' -o seliawake .
```

On PowerShell, with Go on PATH:

```powershell
go test -count=1 ./...
go vet ./...
$env:CGO_ENABLED = '0'
go build -trimpath -buildvcs=false -ldflags '-s -w' -o seliawake.exe .
```

For cross-compilation, set `CGO_ENABLED=0` and the following Go build variables.
Run the same `go build` command with a distinct output name for each target.

| Target | GOOS | GOARCH | GOARM |
|---|---|---|---|
| Windows PC | windows | amd64 | unset |
| Linux PC | linux | amd64 | unset |
| Raspberry Pi, 64-bit OS | linux | arm64 | unset |
| Raspberry Pi, ARMv7 32-bit OS | linux | arm | 7 |
| Intel Mac | darwin | amd64 | unset |
| Apple silicon Mac | darwin | arm64 | unset |

For example, from a POSIX terminal:

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 go build -trimpath -buildvcs=false -ldflags='-s -w' -o seliawake-linux-armv7 .
```

Copy the executable to the destination computer. On Linux or macOS, make your
own copy executable with `chmod 755 ./seliawake`. Run it as your normal user.
You can keep it in your home directory and invoke `./seliawake`, or put it in a
directory already on your PATH. Use an unmodified official release or your
authorized maintainer build. Windows uses `seliawake.exe` and
`.\seliawake.exe`. No service, scheduled task, boot startup, firewall rule, or
system installer is created. Keep Tailscale separately installed and connected.

## Set up a Waker

The Waker stays powered on and awake on the target's physical LAN. A laptop or PC
can serve this role. A sleeping computer cannot relay its own wake request.
Choose its assigned Tailscale IPv4 and physical LAN IPv4 from the operating
system's network settings. The CLI checks local interface assignments without
probing other devices. It cannot prove that an RFC1918 interface is physical;
select the Ethernet or Wi-Fi address yourself, not another VPN interface.

```sh
./seliawake init-waker --tailnet-ip 100.101.102.103 --lan-ip 192.168.1.20 --mac 02:11:22:33:44:55 --broadcast 192.168.1.255 --name Home
./seliawake status
./seliawake send-local
./seliawake serve --allow-tailnet
```

Replace the example addresses and MAC. `init-waker` generates a random 256-bit
secret. Both configured addresses must already belong to active local interfaces.
The LAN source must be private IPv4. The broadcast must match that interface's
IPv4 subnet or be `255.255.255.255`, which is the default. Every local send checks
the LAN assignment again, binds UDP to that source IPv4 and sends to port 9.
It never accepts a remote request's target address, MAC, port, or URL.

`serve` requires explicit `--allow-tailnet`. It binds only the configured
`100.64.0.0/10` IPv4 at TCP port `45879`. It rejects missing or stale interface
assignments and bind failures. Stop a GUI relay before starting this CLI relay
on the same Waker. They cannot share the protocol port. Restrict access with
Tailscale policy and any necessary local firewall rule yourself. The CLI makes
no policy changes. IPv6, MagicDNS, subnet-router destinations, and arbitrary
HTTP URLs are not supported.

Commands exit with code `0` on success and code `1` on argument, validation,
configuration, or network failure. Errors go to stderr. `help` exits `0`.
Ctrl+C during `serve` stops the Waker and exits `0`.

Keep the terminal open. Ctrl+C closes the listener and active connections. There
is no autorun. Restarting the Waker clears its in-memory replay and quota state;
a captured signed request can therefore be replayed after restart while still
inside its 30-second freshness window. Avoid restarting during suspected abuse.

## Pair and wake

Export deliberately on the Waker:

```sh
./seliawake export-pairing --show-secret
```

This prints a secret `seliawake://pair?data=...` URI compatible with
`lib/core/protocol.dart`. Anyone holding it can request wakes. Transfer it through
a trusted channel. Terminal scrollback, screenshots, clipboard history, or shell
redirection can retain it. The CLI never prints pairing during init, import,
status, request processing, or errors.

On the User computer:

```sh
./seliawake pair --stdin
```

Paste one URI, then end stdin. On a POSIX terminal use Ctrl+D. On a Windows
console use Ctrl+Z then Enter. Terminal input may be echoed; this is stdin import,
not a hidden password prompt. Do not pass the URI or key as a command argument,
environment variable, or shell command containing the secret. A trusted producer
can pipe the URI directly into `pair --stdin`.

```sh
./seliawake status
./seliawake wake
```

`wake` signs a fresh request and calls only the paired Tailscale IPv4 at
`http://IP:45879/v1/wake`. It ignores proxy environment settings, follows no
redirects, and does no hostname resolution. HTTP is carried inside Tailscale;
HMAC authenticates the request. A completed command reports that the Waker sent
the packet. It does not confirm that the target booted. `status` reads saved
configuration only. It does not claim the relay is running or the target is online.

## Configuration and secrets

The default directory is `seliawake-cli` under Go's `os.UserConfigDir()`:

* Windows: `%AppData%\seliawake-cli`.
* Linux: `$XDG_CONFIG_HOME/seliawake-cli`, otherwise `$HOME/.config/seliawake-cli`.
* macOS: `$HOME/Library/Application Support/seliawake-cli`.

Use `--config-dir DIRECTORY` **before** the command for a separate configuration.
Each configuration has one role and one target. `init-waker` and `pair` create
`config.json` atomically and refuse to replace an existing file, including when
two processes race. They do not import the GUI's storage. To change roles, target,
address, or secret, stop the old Waker and create a new configuration directory.
Re-pair Users after key or Waker-address changes. Deliberately remove the old
directory yourself when no longer needed. Do not edit secrets into shell history.

The key is **plaintext in `config.json`**. There is no OS keychain, encryption,
backup service, or automatic key rotation. Use a trusted local filesystem and
trusted parent directories. Do not place this configuration in a shared or synced
folder. File permissions do not protect against your own account, administrators,
root, disk access, backups, or malware running as you.

On Linux/macOS the CLI requires current-user ownership and no group/other access
on the directory and file. Creation uses directory mode `0700` and file mode
`0600`, subject to a stricter umask. Symbolic links are refused on reads. Filesystems that
cannot provide the required ownership, permissions, or atomic hard-link creation
fail closed.

On Windows it creates a protected DACL granting only the current user full
access, for both directory and file. It verifies owner, protected DACL, exact
single-user access entry, file type, reparse-point status, and link count before
reading secrets. It rejects inherited or broadened ACLs instead of treating
`chmod(0600)` as protection. An existing directory with ordinary inherited ACLs
is refused. Let the CLI create a fresh subdirectory. Unsupported filesystems or
ACL errors fail closed. Files are flushed before an atomic same-directory rename;
existing config files are never replaced.

## Protocol and resource bounds

The wire contract remains [protocol.md](protocol.md). Requests have only integer
`timestamp`, 22-character base64url `nonce`, and 64-character lowercase hex
`signature`. HMAC-SHA256 uses the decoded 32-byte key and the exact UTF-8 message
`timestamp + "\n" + nonce + "\nwake-v1"`. Signature comparison is constant-time.
The CLI rejects duplicate JSON fields, extra request fields, invalid routes,
queries, invalid content types, unknown-length/chunked requests, and bodies over
1024 bytes.

The freshness window is inclusive at 30 seconds. Replay entries last at least
60 seconds and through the timestamp's final accepted second. The cache never
exceeds 128 entries. Only authenticated, fresh, non-replayed requests
consume the desktop quota of 60 per 60 seconds. A valid request that later fails
UDP send still consumes its nonce and quota. Failed UDP sends return `send_failed`,
never `sent`. There is no health endpoint or remote configuration route.

The server allows eight accepted TCP connections, including idle/slow clients.
Excess accepted connections close immediately. Header reads have a two-second
deadline, request reads and response writes have four-second deadlines, keep-alive
is disabled, and connections start with an eight-second deadline. Go's header
limit is configured at 2048 bytes with the standard library's bounded extra
read allowance. Go may reject malformed HTTP or oversized headers before the
JSON handler runs, using its own HTTP error body. Bodies are also bounded while
reading. The client has a four-second connection/header timeout, eight-second
overall timeout, 2048-byte response header limit, and 1024-byte response body
limit. State does not grow with attacker-chosen client addresses.

Tests include the existing Dart HMAC vector, exact pairing JSON/URI, magic-packet
bytes, invalid shapes, freshness boundaries, replay TTL/capacity, valid-only
quota, private config creation, overwrite races, secret redaction, and platform
permission rejection. Real loopback HTTP and UDP sockets exercise a signed
client request through the relay to packet reception. Private test helpers inject
loopback transport addresses; production commands retain all address validation.

Hardware wake still needs separate verification. Target firmware, network
adapter, Ethernet/WoWLAN support, sleep state, router behavior, Tailscale local-LAN
policy, and firewall settings can prevent delivery or boot. A USB charging cable
does not provide a wake-capable LAN connection. Windows CLI production commands
were exercised over the assigned Tailscale and physical Wi-Fi interfaces. A
physical Android Waker accepted a CLI request paired through its QR and sent the
exact 102-byte packet, including with its screen off. Pi/macOS execution and
target boot remain unverified. See [verification.md](verification.md).

API references: [Go net/http](https://pkg.go.dev/net/http),
[Go net](https://pkg.go.dev/net), [Go os](https://pkg.go.dev/os),
[Windows GetSecurityInfo](https://learn.microsoft.com/en-us/windows/win32/api/aclapi/nf-aclapi-getsecurityinfo),
[Windows security descriptor conversion](https://learn.microsoft.com/en-us/windows/win32/api/sddl/nf-sddl-convertstringsecuritydescriptortosecuritydescriptorw),
[Dart String.trim](https://api.dart.dev/dart-core/String/trim.html).
