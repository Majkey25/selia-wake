# Selia Wake

[![Build](https://github.com/Majkey25/selia-wake/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/Majkey25/selia-wake/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/Majkey25/selia-wake?include_prereleases)](https://github.com/Majkey25/selia-wake/releases)
[![Downloads](https://img.shields.io/github/downloads/Majkey25/selia-wake/total)](https://github.com/Majkey25/selia-wake/releases)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20Windows%20%7C%20Linux%20%7C%20CLI-3584e4)](https://majkey25.github.io/selia-wake/terminal.html)
[![License](https://img.shields.io/badge/license-proprietary-555)](LICENSE)

Wake your computer through your own Tailscale devices. One primary action, standard controls, useful icons and no decorative graphics. No Selia Wake account, ads, subscription or developer-operated relay.

[Website](https://majkey25.github.io/selia-wake/) | [Downloads](https://github.com/Majkey25/selia-wake/releases) | [Setup](https://majkey25.github.io/selia-wake/setup.html) | [Terminal](docs/cli.md) | [Privacy](https://majkey25.github.io/selia-wake/privacy.html) | [Support](https://majkey25.github.io/selia-wake/support.html)

## Install

Download an archive from [Releases](https://github.com/Majkey25/selia-wake/releases), verify its SHA-256 against `SHA256SUMS`, and extract the whole archive. Each new release includes the following packages. Historical releases keep their original contents.

| Device | Package | Start |
| --- | --- | --- |
| Android 8+ | `selia-wake-android.apk` | Install the signed APK, or join [invited Google Play internal testing](https://play.google.com/apps/internaltest/4701187673438012050). |
| Windows x64 GUI | `selia-wake-windows-x64.zip` | Open `seliawake.exe` inside the extracted folder. |
| Linux x64 GUI | `selia-wake-linux-x64.tar.gz` | Run `./seliawake`. Requires GTK 3 and an unlocked Secret Service keyring. |
| Windows x64 CLI | `selia-wake-cli-windows-x64.zip` | Run `.\seliawake.exe help` in its extracted folder. |
| Linux x64 CLI | `selia-wake-cli-linux-x64.tar.gz` | Run `./seliawake help`. |
| Linux ARM64 CLI | `selia-wake-cli-linux-arm64.tar.gz` | For a compatible 64-bit OS, including Raspberry Pi OS. |
| Linux ARMv7 CLI | `selia-wake-cli-linux-armv7.tar.gz` | For a compatible 32-bit ARMv7 OS. First-generation Pi Zero and Pi 1 are ARMv6 and need a different build. |

The CLI is a single executable with no Flutter, GTK or keyring dependency. GUI and CLI settings are separate. Run one relay per device because both use TCP 45879. Windows GUI may need the Visual C++ runtime. Google Play is internal testing, not public production.

[ESP32 Arduino companion firmware](docs/esp32.md) is a separate board-specific installation requiring a Tailscale gateway. It is not a universal Arduino binary. Other microcontrollers need their own port and compatible networking; this app cannot install on every device.

## Connect your devices

1. Enable Wake-on-LAN in the target's firmware and connected network adapter. Use the MAC of that adapter. Wi-Fi targets require WoWLAN support in the adapter, driver and firmware. [Wireless setup](https://majkey25.github.io/selia-wake/setup.html#wowlan) includes the Windows checks. A normal phone charging cable does not provide USB remote wake.
2. Install Tailscale separately on your always-awake **Waker** and remote **User** device. Connect both to your tailnet. Keep the Waker on the target's physical LAN. A spare phone, laptop, desktop or Raspberry Pi can fill this role. The sleeping target cannot be its own Waker.
3. In the home device's Settings, choose The Waker, enter the target MAC, LAN broadcast and Waker Tailscale IPv4. On desktop, also confirm its physical LAN source IPv4. Save and start it. Android uses a visible foreground service. Desktop GUI must stay open. Check laptop sleep and lid-close settings yourself.
4. Open Pairing link / QR on The Waker. On User, scan on Android or paste the link, review the name and address, then save. Both forms contain the same secret. Transfer them privately. Camera frames stay on-device; clipboard access requires an explicit action.
5. Press Wake. “Packet sent” confirms a UDP send, not that the target booted. Keep the Waker powered and Tailscale connected. No automatic startup or firewall changes are installed.

## Use the terminal

From the extracted CLI folder, configure an always-on Waker. Replace the example values with its own network addresses and the target MAC:

```sh
./seliawake init-waker --tailnet-ip 100.101.102.103 --lan-ip 192.168.1.20 --mac 02:11:22:33:44:55 --broadcast 192.168.1.255 --name Home
./seliawake export-pairing --show-secret
./seliawake serve --allow-tailnet
```

On the User computer, run `./seliawake pair --stdin`, paste the private pairing URI, then end input with Ctrl+D on Linux or Ctrl+Z and Enter on Windows. Run `./seliawake wake`. Use `.\seliawake.exe` on PowerShell. Never put the secret URI in a command argument or shell history. See the [CLI reference](docs/cli.md) for configuration, local sends, exit codes and limits.

## Appearance

Platform style is the default. Android uses Material 3 with dynamic colors where available. Windows uses Fluent controls. Linux uses standard Flutter controls with a desktop palette. Flutter renders these controls itself; they are not OS-owned GTK or WinUI widgets.

Material You, Terminal, Matrix and Custom are available. Custom exposes accent, background, surface, text, secondary text, borders and error colors, font family, size, corner radius and border width. Preview before saving. Light, dark and system modes remain available; Matrix is dark and Custom keeps your chosen palette. English and Czech app UI. Public pages and documentation are English.

## Network and storage

Wake requests use HMAC-SHA256, a 30-second freshness window and a bounded replay cache. Only valid fresh requests consume the wake quota. Remote requests cannot select the target MAC or destination. The listener is TCP 45879; local magic packets use UDP 9. The pairing key is not transmitted in wake requests. Tailscale provides remote transport encryption. The LAN broadcast is not encrypted.

The GUI uses OS secure storage. The CLI uses an unencrypted local configuration file protected by owner-only permissions or a strict Windows ACL. Protect backups and avoid shared or synced folders. The CLI binds its listener to the configured Tailscale IPv4; GUI listener access also needs firewall and tailnet restrictions. Never forward the relay to the public internet or publish it through Funnel. VPN policy must allow the Waker to send to its physical LAN.

[Protocol](docs/protocol.md) | [Security review](docs/security-audit.md) | [Verification record](docs/verification.md) | [Data removal](https://majkey25.github.io/selia-wake/delete-data.html)

## Maintainer builds

Source inspection is public. Building new proprietary material requires license permission, except for the personal ESP32 build permission in [LICENSE](LICENSE). Historical MIT material keeps its earlier grant.

GUI toolchain: Flutter 3.47.8, Dart 3.13.7, JDK 17, Android SDK 36. Build desktop targets on their own OS. Linux needs Clang, CMake, Ninja, pkg-config, GTK 3 and libsecret development files. Windows needs Visual Studio C++ desktop tools including ATL.

```sh
flutter pub get
flutter analyze
flutter test
flutter build windows --release
flutter build linux --release
flutter build apk --release
flutter build appbundle --release
```

Android signing uses ignored `android/key.properties` and a private upload keystore. Release builds do not fall back to debug signing. CLI uses the Go standard library; see [build commands](docs/cli.md). GitHub Actions tests and packages Windows/Linux GUI and CLI architectures. [Release instructions](docs/releases.md) require all installation packages before publishing.

## License

New original material uses the [Selia Wake Source-Visible Proprietary License](LICENSE), based on SeliaScan's license. Official releases may be installed and used under its terms. [Historical MIT grants](HISTORICAL_MIT_RELEASES.md) remain valid. Dependencies retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
