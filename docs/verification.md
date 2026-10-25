# Verification, 23 October 2026

- Flutter 3.47.8, Dart 3.13.7, JDK 17, Android target SDK 36.
- `flutter analyze` passed. Six protocol tests and one widget test passed. The widget test checks all three themes in light and dark mode on a 360 x 640 Czech screen.
- Signed Android APK and AAB built. APK installed on a physical HUAWEI YAL-L21 with Android 10 over USB.
- The phone detected its physical Wi-Fi and Tailscale IPv4 addresses. Start, stop, saved settings, English/Czech, Glass/dark appearance, and ten sequential relay restart cycles were exercised.
- A signed request to the phone's Tailscale address produced the exact 102-byte magic packet at an independent Windows UDP listener. Its source was the phone's physical Wi-Fi address. A repeated nonce returned 409; a bad signature and expired request returned 401; malformed JSON shape returned 400.
- A second request worked with the phone app in the background and its screen off. This is a spot check, not a long-duration availability guarantee.
- The production Dart User client also reached the physical Android Waker, with the LAN packet observed independently. The desktop Dart Waker was exercised with real HTTP and UDP, invalid credentials, and listener shutdown in a local Flutter test runner.
- An Android transport failure was reproduced as `Network.bindSocket` returning `EPERM` under Tailscale. Binding the physical Wi-Fi IPv4 source address resolved it. Temporary diagnostic code and test entry points are not part of the application source.
- GitHub Actions built Windows x64 and Linux x64 on their respective operating systems. The downloaded Windows binary launched locally and remained responsive. Native Windows GUI interaction was not automated.
- A bounded read-only protocol fact-check by GLM 5.3 Flash at high reasoning found no confirmed P1/P2 protocol or lifecycle defects. Findings were checked against source; model output is not runtime proof.

## Limits

The development computer was not suspended or shut down. Hardware wake, BIOS settings, and wake from complete shutdown are unverified. The computer's Ethernet link was disconnected during setup.

Linux GUI runtime was not tested locally. `wsl --list --quiet` reported that Windows Subsystem for Linux is not installed. A Linux desktop with GTK 3 and an unlocked Secret Service keyring is needed for that acceptance check.

Google Play internal-track availability must be checked in Play Console separately from these builds and GitHub distribution.

## 24 October 2026, version 0.1.1

- Replaced the decorative home screen with a bordered panel, one rectangular primary action, and Terminal, Material You and Matrix themes. Existing unknown/Glass preferences migrate to Terminal while preserving pairing and target data.
- `flutter analyze`, nine tests, and signed release APK/AAB builds passed. Tests include the unauthenticated-quota regression, authenticated limit, replay checks, small Czech screen across all themes, and encrypted-settings migration.
- Installed the release APK on the physical HUAWEI YAL-L21. Terminal light/dark, navigation, QR display, denied camera permission, retry with permission, camera open and cancellation were exercised. Android camera service confirmed the camera was released after cancellation. The displayed QR decoded locally with ZXing to the expected pairing URI; optical scanning from a second device was not exercised.
- The real Android relay passed the unauthenticated-quota attack test described in the security audit. An independent Windows UDP listener received the configured magic packets from the phone's physical Wi-Fi address through signed requests to its Tailscale address.
- A further signed request produced the correct 102-byte packet while Selia Wake was in the background and the phone screen was off. This remains a spot check.
- The target PC's Ethernet adapter was disconnected, while its configured MAC belonged to that Ethernet adapter. Windows listed that Ethernet device as wake-armed, but not the active Wi-Fi adapter. The disconnected target link prevents this Ethernet wake path. BIOS configuration and actual wake after reconnecting Ethernet remain unverified. A phone charging cable does not substitute for that connection.
- Two bounded independent source-review rounds found and then verified the quota fix. The final review found no remaining confirmed P1/P2 within its scope; it did not independently execute builds or device tests.

## 24 October 2026, version 0.1.2

* The Windows Wi-Fi wake-enable command was run through UAC. A fresh `powercfg /devicequery wake_armed` includes the MediaTek MT7922. This confirms Windows configuration, not a successful hardware wake.
* Added the Windows WoWLAN setup and diagnostic commands to the offline English/Czech app guide. The physical Android release opened the guide and exposed the commands. Settings also opened the new offline Privacy & support page with the expected text.
* Dart analysis, formatting, nine local tests, signed Android APK/AAB builds, bundle validation, APK signature verification and 16 KB zip alignment passed.
* GitHub Actions run 40072210858 passed verification and built Windows and Linux from commit 766b00bbe05d2ede9feef444e928b635aa0d55a5. Subsequent website-only copy edits do not change application source.
* All five public HTML pages returned HTTP 200, as did the shared CSS. The website was checked in a real browser at desktop and 360 px mobile width, including navigation, the WoWLAN commands, contact and removal pages. Mobile pages had no horizontal document overflow. Privacy policy URL in Play Console matches the public page.
* Physical PC sleep/wake, Linux GUI runtime and full desktop GUI flows remain unverified. The website and internal releases do not establish production Google Play approval; additional Play Console declarations remain separate.

## 24 October 2026, version 0.2.0

* Added platform-style Flutter controls, Fluent controls on Windows, Material
  You, Terminal, Matrix and a custom palette/font/size/corners/borders editor.
  These are Flutter-rendered controls, not OS-owned WinUI or GTK widgets.
* All 27 Flutter tests passed locally. Two Android JVM tests passed, including
  the future-timestamp replay regression and exact minimum-TTL reuse. The
  regression failed before the fix in Go, Dart and Android.
* Windows Go tests and vet passed. Production CLI commands were exercised
  through real Tailscale HTTP and physical Wi-Fi UDP, with exact 102-byte magic
  packets received independently. No target sleep or boot was attempted.
* On the physical HUAWEI YAL-L21, custom colors and corner radius saved,
  survived force-stop/relaunch, reset correctly, and saved while the Waker was
  running with a successful stop/restart. Existing target and pairing survived
  the update. The phone was left in Platform style with its Waker running.
* The final signed ARM64 release APK was installed over the existing app. Its
  QR was decoded privately in memory and imported by the production Windows
  CLI. Two signed requests through Tailscale produced the exact configured
  packet from the phone's physical Wi-Fi, including with its screen off.
  No pairing secret or QR image was retained in the test evidence.
* Universal and per-ABI Android APKs and the AAB built. Signature verification
  matched the existing upload certificate; universal APK 16 KB zip alignment
  and bundle validation passed. ARM64 APK size is about 18.4 MB.
  All final Android packages use version code 3006. ABI offsets are disabled
  so GitHub APKs cannot block later Google Play updates with a higher code.
* All six English HTML pages and CSS returned HTTP 200 locally. Local links
  and anchors passed validation. Real browser checks at desktop and 360 px
  mobile width found no horizontal document overflow.
* Optional Claude review could not run because of its weekly quota. Requested
  Argon high and Muse xhigh OpenCode calls failed with HTTP 402 and an account
  balance of zero. No funds were added. Free Beam, DeepSeek and GLM provided
  bounded documentation advice; primary checked their claims. Antigravity
  supplied the initial ESP32 implementation, which required primary fixes.
* A fresh isolated ESP32 Arduino core 3.3.12 build passed for
  `esp32:esp32:esp32`: 945,693 bytes of program space and 53,236 bytes of global
  data. An earlier cached core link failed on ESP symbols; the isolated build
  did not reuse that cache. Separate bounded CLI/protocol and ESP32 source
  reviews found no remaining confirmed P1/P2 in their supplied snapshots.
* Linux GUI execution, Raspberry Pi execution, ESP32 flashing/on-board behavior,
  sustained background availability and actual PC wake remain separate checks.
  The local Windows GUI build remains blocked by missing ATL `atlstr.h`.

## 24 October 2026, local version 0.2.1

* Added optional direct TCP target checks to the GUI. Existing records default
  to disabled. User wake waits up to 60 seconds for the selected service.
  A response proves reachability, not host identity, boot completion or login.
  Pairing and relay protocol v1 are unchanged. CLI and ESP32 are unchanged.
* All 32 Flutter tests passed, including real TCP listener/closed-port checks,
  bounded waiting, delayed service start, cancellation and settings migration.
  Flutter analysis, formatting and `git diff --check` passed.
* Signed ARM64 Android 0.2.1 (3007) built and installed over 0.2.0 on the USB
  HUAWEI YAL-L21. Signature matched the existing certificate and APK 16 KB zip
  alignment passed. Existing target, pairing and appearance survived the update.
* On that phone, Check PC reached the development PC's RDP service through
  Tailscale. A different port returned the inconclusive no-response message.
  Backgrounding interrupted a pending check without showing a stale result.
  Availability settings survived a process restart.
* Before and after the update, a real signed HTTP request through Tailscale
  returned 200 and the awake PC independently received the exact configured
  102-byte magic packet from the phone's physical Wi-Fi address. The QR and
  pairing key were decoded in memory and were not retained in evidence.
* The development PC reports ASUS PRIME B450-PLUS, MT7922 Wi-Fi, S3 sleep,
  enabled Wake on Magic Packet and an armed Wi-Fi device. These do not prove
  that firmware and the complete PCIe/Wi-Fi path can wake from S3. BIOS APM
  settings were not accessible from this session. No sleep or reboot of the
  development PC was attempted. Physical wake remains unverified.
* A prompt-only Claude source review with tools disabled could not run because
  its weekly quota was exhausted. Primary self-review and runtime checks are
  the available evidence. No desktop build, Linux GUI run or Google Play/GitHub
  publication was performed for this local version.

## 25 October 2026, Sleeper and awake-PC diagnostics

* Windows inspection identifies the active physical MT7922 Wi-Fi adapter and
  its correct MAC and directed broadcast. Both wake arming and the recognized
  Magic Packet property were already enabled. Inspect and idempotent Enable
  returned fresh JSON without changing settings or restarting the adapter.
* A real click on Wake in the installed Windows User GUI sent through its
  existing paired Android Waker. An independent UDP listener on this awake PC
  received the exact 102-byte magic packet from the phone's physical Wi-Fi.
  This proves this awake network path, not successful hardware wake.
* Two explicitly authorized S3 tests were performed before the user requested
  awake-only debugging. First, the phone independently made three signed HTTP
  wake requests and received three 200/sent responses while the PC slept. The
  PC later resumed from a USB device, after about 66 seconds.
* Second, the phone sent the exact packet directly to the target's LAN IPv4
  at 30, 35 and 40 seconds. The PC resumed only from the absolute UTC fallback
  timer, after about 92 seconds. Fresh Windows sleep/wake event timestamps and
  phone send timestamps were correlated for both runs. Neither test succeeded
  in waking this Wi-Fi/S3 setup. BIOS, firmware and driver compatibility remain
  unresolved; no absence of capability on all MT7922 systems is inferred.
* After the user requested awake-only debugging, no further suspend, shutdown
  or restart was requested. No permanent power policy or firewall was changed.
* Before final UI revisions, 58 Flutter tests, Flutter analysis, two Android
  JVM tests, Windows Go tests/vet, and signed APK/AAB builds passed. Final
  release validation is recorded separately after the review fixes and UI.
* Independent MPT Astra xhigh source review found three P2 correctness issues:
  imported target setup could save indirectly; Linux selection did not carry
  displayed adapter identity across privilege approval; Windows /31 and /32
  prefixes incorrectly produced broadcast addresses. Release remains gated on
  fixes, regression checks and a follow-up source review.
* MajkeyLab Astra max implemented Windows inspection/configuration; MajkeyLab
  Sol 6.1 xhigh implemented the GUI; MPT Sol 6.1 max implemented the portable
  core. Antigravity supplied bounded English documentation. OpenCode Argon high
  failed with HTTP 402, insufficient funds. No funds were added. Beam xhigh and
  DeepSeek high supplied bounded test advice, checked against source and runtime.

### Final review fixes and local checks

* Pending Sleeper imports now block pairing export and local test actions until
  explicit Save. Regression coverage verifies that these actions cannot commit
  a preview indirectly. Settings has grouped sections, a header Save action,
  more icons and actual previews for all five theme choices.
* Linux enable now requires the displayed MAC, carries the OS interface index,
  revalidates physical sysfs identity inside the reviewed helper after polkit
  approval, and verifies the same device afterward. Helper fixture tests run
  real Bash validation, including startup/environment injection rejection.
* Windows /31 and /32 prefixes now report no broadcast. Five live helper cases
  passed, and the UI disables target export when broadcast is unknown.
* Pairing export and local testing also block unsaved appearance changes,
  including custom color edits. Two regressions failed before the fix and
  passed afterward. Failed saves do not advance the saved appearance snapshot.
* All 82 Flutter tests and final Flutter analysis passed.
  A separate local integration test executed Sleeper.inspect through Flutter's
  real bundled PowerShell asset and parsed the physical Windows adapter report.
* A separate Claude prompt-only review returned no answer after 24 minutes and
  was cancelled. It supplied no verdict. MPT Astra r2 confirmed the first three
  fixes and found the appearance save issue. MPT Astra r3 confirmed that fix
  with no remaining confirmed P1/P2 in its bounded source snapshot. These
  source reviews did not independently execute tests or prove hardware wake.

### Automatic settings update, version code 3010

* The user replaced explicit Save with automatic application of valid edits.
  Settings now saves after a short typing pause. Revert changes restores the
  snapshot from when the page opened. Reset defaults clears connection and
  target details, restores default appearance and rotates the Waker key.
  Revert can restore that key while the same Settings page remains open.
* Writes are serialized and use immutable snapshots. A new regression types
  during a pending write and presses Back; the latest value persists before
  navigation completes. Invalid fields do not save. Appearance-only changes
  preserve the running Waker instead of stopping and restarting it.
* All 89 Flutter tests and Flutter analysis passed. The suite includes automatic
  import, explicit clipboard access, invalid custom values, reset/key rotation,
  Revert, failed persistence and pending-write navigation. These tests do not
  establish hardware wake or successful privileged OS mutation.
* MPT Astra r4 found two P2 races. The parent now tracks its last successfully
  persisted settings immediately, so consecutive saves do not compare against
  a widget awaiting rebuild. Pending clipboard results are discarded after a
  newer edit, reset or departure. Regressions cover active relay A/B/A ordering,
  appearance without restart and a delayed Paste completing after Reset.
* MPT Astra r5 confirmed both race fixes with no remaining confirmed P1/P2 in
  its source snapshot. Primary's full 89-test run passed after the fixes.
* On the physical HUAWEI YAL-L21 running signed build 3010, choosing Matrix
  applied the theme without Save. Revert restored the opening Platform theme
  and removed its button. The foreground service retained the same Android
  ServiceRecord, creation time and start ID through both appearance writes.
  The existing target, pairing and Czech/light preferences were preserved.
* Terminal selection also survived force-stop/relaunch. Platform was restored
  afterward and the Waker was left running. Final package code 3011 only
  corrects an obsolete Save instruction in the desktop target-sharing dialog
  and removes its unused translation. Version code 3010 remains an unpublished
  Play artifact; it is not substituted with different bytes.
