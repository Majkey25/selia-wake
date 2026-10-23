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
