# Selia Wake

One button to wake your computer through your own Tailscale devices. Android, Windows, and Linux. No account, subscription, cloud relay, or telemetry.

[Downloads](https://github.com/Majkey25/selia-wake/releases) · [Privacy](https://majkey25.github.io/selia-wake/privacy.html)

## The two roles

**The Waker** stays awake at home, on the same local network as the computer you want to wake. Configure the computer's Ethernet MAC address, enable the Waker, and copy its pairing code.

**User** runs on the device you carry. Connect Tailscale, paste the pairing code in Settings, and press Wake. The Waker receives the signed request and sends the local magic packet.

The same application supports both roles. You do not need the app running on the sleeping computer. The Waker cannot be that sleeping computer.

## Setup

1. Enable Wake-on-LAN in the target computer's firmware and Ethernet driver. First test from sleep. Wake from shutdown depends on the hardware.
2. Connect the target computer to your router or switch by Ethernet. A USB cable from a phone is not an Ethernet connection. Wireless wake support is hardware-specific.
3. Install Tailscale separately on the Waker and User devices. Sign in to your own tailnet and allow the devices to communicate.
4. On your home device, select The Waker. Enter the target name and Ethernet MAC address. The default broadcast is selected from Wi-Fi on Android. On desktop, confirm the physical LAN IPv4 address; automatic detection is only a starting point on computers with several adapters.
5. Enter the Waker's Tailscale IPv4 address, enable it, and copy its pairing code to the User device. Pairing codes contain a secret. Share them only with trusted devices.
6. Keep the Waker awake and connected. Android shows a persistent notification with a Stop action. Desktop relay operation lasts while the application is open. The Waker does not start automatically after a reboot.

On Android phones with restrictive battery management, allow background operation for both Selia Wake and Tailscale. A visible foreground service is not a guarantee against manufacturer battery restrictions. Power a dedicated home phone from a wall charger.

The message **Packet sent** confirms transmission. It does not confirm that the target computer booted.

## Appearance

Material You, Glass, and Terminal themes. Light, dark, and system appearance. English and Czech. Reduced-motion settings disable animation. The optional short RGB glitch treatment follows the user's WeTheGods visual style.

## Security and network

Pairing keys live in operating-system secure storage. Wake requests use HMAC-SHA256, a 30-second timestamp window, bounded replay protection, and request limits. The pairing secret is never transmitted in a wake request. A remote request cannot choose a different MAC address or destination.

The Waker listens on TCP **45879** and sends magic packets on local UDP **9**. Tailscale supplies transport encryption. The app does not embed Tailscale, change your firewall, configure your router, or open public internet ports. If a desktop firewall blocks the Waker, allow only your intended Tailscale peers. Do not forward the relay port from the public internet.

Android broadcasts use the physical Wi-Fi network rather than the VPN route. Guest Wi-Fi or access-point isolation can block communication between wireless and wired devices.

## Build

Flutter **3.47.8**, Dart **3.13.7**, JDK **17**, Android SDK **36**. Android minimum version is **8.0 / API 26**.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build windows --release
flutter build linux --release
```

Build each desktop target on its own operating system. Linux builds need Clang, CMake, Ninja, pkg-config, GTK 3 development files, and libsecret development files. Linux runtime needs GTK 3 and an unlocked Secret Service-compatible keyring. Windows builds need Visual Studio's C++ desktop tools including ATL headers for the secure-storage plugin. Windows runtime may need Microsoft's Visual C++ runtime.

Release signing is local. Copy `android/key.properties.example` to `android/key.properties` and provide your own upload keystore. Neither file nor keystore belongs in Git. Release builds deliberately do not fall back to the debug signing key.

```sh
flutter build apk --release
flutter build appbundle --release
```

GitHub Actions checks the Dart sources and builds portable Windows and Linux archives. Android publication uses the locally signed bundle. A successful build or GitHub release does not establish Google Play availability.

## References

- [Tailscale's explanation of Wake-on-LAN relays](https://tailscale.com/blog/wake-on-lan-tailscale-upsnap)
- [ASUS firmware Wake-on-LAN setup](https://www.asus.com/support/faq/1045950/)
- [Protocol and platform contract](docs/protocol.md)

MIT license. Space Grotesk is bundled under its SIL Open Font License in `assets/fonts/OFL.txt`.
