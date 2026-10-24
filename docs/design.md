# Selia Wake

Android, Windows, and Linux. Flutter Material 3 UI. No account or cloud backend. Tailscale stays a separate installed application.

## Roles

- The Waker stays awake on the target LAN and receives authenticated requests through Tailscale. It sends a standard UDP magic packet on the physical LAN.
- User stores a paired Waker and presses Wake. Settings hold the Waker address and pairing secret. Devices can switch roles.
- A sleeping computer cannot relay its own wake request. USB charging is not an Ethernet connection. Wake capability depends on the target firmware and network adapter.

## Protocol

One configured target per Waker. Pairing transfers an address and a random 256-bit secret. Requests contain a timestamp, random nonce, and HMAC-SHA256 signature. The secret never travels in a wake request. Reject invalid signatures, expired requests, duplicate nonces, oversized bodies, and excess requests. Replay memory is bounded and expires. Wakers never accept arbitrary destinations from requests.

Android runs the Waker in a visible foreground service. Its native service owns the relay and binds UDP to the physical Wi-Fi network, independent of Flutter activity lifetime. Windows and Linux run the relay while the desktop app stays open. No silent background daemon or firewall changes.

Success means the magic packet was sent, not that the computer booted. Display failures explicitly. No telemetry, ads, analytics, contact access, or third-party servers.

## Interface

One rectangular action, target name, honest status, and a settings link in a compact ruled panel. Role selection lives in Settings. Terminal is the default; Material You and Matrix are alternatives. Terminal and Material You support light, dark, and system appearance. Matrix is always black with green text. English and Czech UI.

Terminal uses black, white, IBM Plex Mono, thin borders, and square controls, following the user's export-panel reference. Material You uses system colors, sans-serif type, and standard rounded controls. Matrix uses #75F59B on black. No decorative background, glass, RGB split, or animation.

Pairing links and QR codes carry the same validated Tailscale IPv4, target name, and secret. Every platform can display a QR; Android can scan using its camera. Windows and Linux import the copied link. Scanned data is shown for review and is not saved until Save settings. Camera images stay on-device and are not saved. Setup instructions explain Tailscale, target hardware, Ethernet, WoWLAN, and USB Ethernet requirements; a phone charging cable is not a remote-wake transmitter.

## Delivery and verification

GitHub source and downloadable Android, Windows, and Linux builds. Signed Android App Bundle for Google Play internal testing. Application ID com.majkeylab.seliawake. Wakeit already names existing Wake-on-LAN tools, so use the user's fallback name Selia Wake.

Check protocol rejection paths, actual UDP payload and destination, role lifecycle, persistence, settings, themes, localization, Android screen-off operation, and a real Windows-to-phone relay request. Do not suspend the development PC. Actual hardware wake remains unverified until a separate target and observer are available.
