# Selia Wake

Android, Windows, and Linux GUI, plus a small standalone Go CLI for Windows and Linux including ARM64 and ARMv7. No app account or developer-operated backend. Tailscale stays a separate installed application. ESP32 uses companion firmware and a separate Tailscale gateway.

## Roles

- The Waker stays awake on the target LAN and receives authenticated requests through Tailscale. It sends a standard UDP magic packet on the physical LAN.
- User stores a paired Waker and presses Wake. Settings hold the Waker address and pairing secret. Devices can switch roles.
- The Sleeper is available on Windows and Linux desktop to configure the target computer itself. It inspects OS sleep states and physical network adapters, and enables OS-level Wake-on-LAN settings. It exports a target setup QR code or link for The Waker. Sleeper does not keep the computer awake, run a relay, or install background services. BIOS and firmware wake capabilities cannot be verified by software alone. Switching away from Waker stops the relay.
- A sleeping computer cannot relay its own wake request. USB charging is not an Ethernet connection. Wake capability depends on the target firmware and network adapter.

## Protocol

One configured target per Waker. Pairing transfers an address and a random 256-bit secret. Requests contain a timestamp, random nonce, and HMAC-SHA256 signature. The secret never travels in a wake request. Reject invalid signatures, expired requests, duplicate nonces, oversized bodies, and excess requests. Replay memory is bounded and expires. Wakers never accept arbitrary destinations from requests.

Android runs the Waker in a visible foreground service. Its native service owns the relay and binds UDP to the physical Wi-Fi network, independent of Flutter activity lifetime. Windows and Linux run the relay while the desktop app stays open. The CLI serves until Ctrl+C and binds only its configured Tailscale IPv4. GUI and CLI settings are separate. No automatic startup or firewall changes are installed.

Success means the magic packet was sent, not that the computer booted. Display failures explicitly. No telemetry, ads, analytics or contact access. The ESP32 companion uses external NTP time services; Tailscale remains a separate service.

GUI users can optionally configure the target PC's private or Tailscale IPv4 and an existing TCP service port. Check PC attempts a bounded TCP connection directly from the app, without sending credentials or application data. After a successful wake request, the User GUI retries for up to 60 seconds while foregrounded. Closing, backgrounding or cancelling the check suppresses late results. A successful connection confirms service availability, not boot completion, host identity or login. Failure is inconclusive because a firewall or stopped service has the same result as sleep. Check settings remain local and do not change pairing or relay protocol v1. The CLI and ESP32 protocol remain unchanged.

Target setup export uses the URI scheme `seliawake://sleeper?data=<base64url>` containing computer name, MAC address, LAN broadcast, connection type, and optional target host IPv4 and TCP port. It contains network details but no secret keys or execution commands. The Waker imports this URI via explicit clipboard paste or QR scan, previews the parameters, and applies them only upon explicit Save. The Waker also offers a local test packet action in Settings that saves configuration and sends an immediate UDP magic packet to the local LAN while remaining awake, allowing physical sleep testing without remote pairing.

## Interface

One primary action, target name, honest status, and a settings icon. Role selection lives in Settings. Platform style is the default. Android uses Material 3 and dynamic colors. Windows uses Fluent controls. Linux uses standard Flutter controls with a desktop palette. Flutter renders all these controls itself; this is not an OS-owned GTK or WinUI widget implementation.

Material You, Terminal, Matrix and Custom are alternatives. Terminal uses IBM Plex Mono and thin borders. Matrix uses green on black. Custom exposes a full application palette, font family and size, corner radius and border width, with draft preview and validation before Save. Its draft does not mutate saved settings. Custom keeps one chosen palette across brightness modes. OS permission dialogs are unaffected. Existing theme choices and pairing keys survive upgrades. English and Czech app UI; English public pages and documentation. No decorative backgrounds or animation.

Pairing links and QR codes carry the same validated Tailscale IPv4, target name, and secret. Every platform can display a QR; Android can scan using its camera. Windows and Linux import the copied link. Scanned data is shown for review and is not saved until Save settings. Camera images stay on-device and are not saved. Setup instructions explain Tailscale, target hardware, Ethernet, WoWLAN, and USB Ethernet requirements; a phone charging cable is not a remote-wake transmitter.

Clipboard access is strictly explicit: reading occurs only during Paste, and writing occurs only during Copy. On Windows and Linux, the Sleeper page lists active physical IPv4 adapters and reports OS wake settings. Enabling wake mutates only the selected adapter using standard system tools (`powercfg` on Windows, `ethtool` on Linux). Linux `ethtool` settings apply to the running system and may require NetworkManager configuration to persist across reboots. The app never installs automatic startup items or mutates system firewalls.

## Delivery and verification

Source-visible proprietary material and downloadable official Android, Windows, Linux and CLI releases. Earlier MIT grants and third-party licenses remain valid. Signed Android App Bundle for Google Play internal testing. Application ID com.majkeylab.seliawake. Wakeit already names existing Wake-on-LAN tools, so use the user's fallback name Selia Wake. Version 0.3.0 adds the Sleeper role, target setup exchange and theme previews in Settings.

Check protocol rejection paths, actual UDP payload and destination, role lifecycle, persistence, settings, themes, localization, Android screen-off operation, and a real Windows-to-phone relay request. A physical sleep test needs explicit authorization, an independent awake sender, an armed fallback wake timer and wake-source evidence. OS configuration and packet delivery alone do not establish hardware wake.
