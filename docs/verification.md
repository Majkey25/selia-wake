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
