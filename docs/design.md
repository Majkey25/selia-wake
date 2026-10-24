# Selia Wake

Android, Windows, and Linux GUI, plus a small standalone Go CLI for Windows and Linux including ARM64 and ARMv7. No app account or developer-operated backend. Tailscale stays a separate installed application. ESP32 uses companion firmware and a separate Tailscale gateway.

## Roles

- The Waker stays awake on the target LAN and receives authenticated requests through Tailscale. It sends a standard UDP magic packet on the physical LAN.
- User stores a paired Waker and presses Wake. Settings hold the Waker address and pairing secret. Devices can switch roles.
- A sleeping computer cannot relay its own wake request. USB charging is not an Ethernet connection. Wake capability depends on the target firmware and network adapter.

## Protocol

One configured target per Waker. Pairing transfers an address and a random 256-bit secret. Requests contain a timestamp, random nonce, and HMAC-SHA256 signature. The secret never travels in a wake request. Reject invalid signatures, expired requests, duplicate nonces, oversized bodies, and excess requests. Replay memory is bounded and expires. Wakers never accept arbitrary destinations from requests.

Android runs the Waker in a visible foreground service. Its native service owns the relay and binds UDP to the physical Wi-Fi network, independent of Flutter activity lifetime. Windows and Linux run the relay while the desktop app stays open. The CLI serves until Ctrl+C and binds only its configured Tailscale IPv4. GUI and CLI settings are separate. No automatic startup or firewall changes are installed.

Success means the magic packet was sent, not that the computer booted. Display failures explicitly. No telemetry, ads, analytics or contact access. The ESP32 companion uses external NTP time services; Tailscale remains a separate service.

## Interface

One primary action, target name, honest status, and a settings icon. Role selection lives in Settings. Platform style is the default. Android uses Material 3 and dynamic colors. Windows uses Fluent controls. Linux uses standard Flutter controls with a desktop palette. Flutter renders all these controls itself; this is not an OS-owned GTK or WinUI widget implementation.

Material You, Terminal, Matrix and Custom are alternatives. Terminal uses IBM Plex Mono and thin borders. Matrix uses green on black. Custom exposes a full application palette, font family and size, corner radius and border width, with draft preview and validation before Save. Its draft does not mutate saved settings. Custom keeps one chosen palette across brightness modes. OS permission dialogs are unaffected. Existing theme choices and pairing keys survive upgrades. English and Czech app UI; English public pages and documentation. No decorative backgrounds or animation.

Pairing links and QR codes carry the same validated Tailscale IPv4, target name, and secret. Every platform can display a QR; Android can scan using its camera. Windows and Linux import the copied link. Scanned data is shown for review and is not saved until Save settings. Camera images stay on-device and are not saved. Setup instructions explain Tailscale, target hardware, Ethernet, WoWLAN, and USB Ethernet requirements; a phone charging cable is not a remote-wake transmitter.

## Delivery and verification

Source-visible proprietary material and downloadable official Android, Windows, Linux and CLI releases. Earlier MIT grants and third-party licenses remain valid. Signed Android App Bundle for Google Play internal testing. Application ID com.majkeylab.seliawake. Wakeit already names existing Wake-on-LAN tools, so use the user's fallback name Selia Wake.

Check protocol rejection paths, actual UDP payload and destination, role lifecycle, persistence, settings, themes, localization, Android screen-off operation, and a real Windows-to-phone relay request. Do not suspend the development PC. Actual hardware wake remains unverified until a separate target and observer are available.
