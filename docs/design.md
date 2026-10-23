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

One primary power button, a target name, honest connection/result status, role selector, and settings. Material, Glass, and Terminal themes. Light, dark, and system appearance. English and Czech UI. Material icons with accessible labels.

Palette: midnight #151A25, ice #B4D9F8, slate #8593A7, paper #F4F6FA, graphite #253043, signal #E2AA85. Material uses rounded controls; Glass uses restrained translucent surfaces; Terminal uses monochrome rules inspired by the supplied reference. One short RGB split animation on the power button, adapted from the user's WeTheGods visual treatment. Background motion stays sparse and stops with reduced motion or the motion setting.

## Delivery and verification

GitHub source and downloadable Android, Windows, and Linux builds. Signed Android App Bundle for Google Play internal testing. Application ID com.majkeylab.seliawake. Wakeit already names existing Wake-on-LAN tools, so use the user's fallback name Selia Wake.

Check protocol rejection paths, actual UDP payload and destination, role lifecycle, persistence, settings, themes, localization, Android screen-off operation, and a real Windows-to-phone relay request. Do not suspend the development PC. Actual hardware wake remains unverified until a separate target and observer are available.
