# Google Play listing copy

The English and Czech text in `en-US/` and `cs-CZ/` describes source commit `833a7262f28ffcf203e683dc6f8ef7a0f816e482` (0.1.2+4). It is listing copy, not evidence of a device test, hardware compatibility or Google Play approval.

Each locale contains a title, short description and full description as plain UTF-8 text. These files contain no donation links. Keep the hardware requirements and the distinction between packet transmission and confirmed boot in both translations.

## Existing icon

Use the project's existing [512 × 512 icon](../../assets/icon-512.png) from `assets/icon-512.png`. The icon was visually checked at its native size. This change adds no new artwork or screenshots.

## Source references

| Listing fact | Source |
| --- | --- |
| User and Waker roles, one-button wake | `lib/ui/home.dart`, `lib/core/settings.dart` |
| QR scan, link paste, built-in guide | `lib/ui/settings_page.dart`, `lib/ui/setup_guide.dart` |
| Themes and appearance limits | `lib/ui/theme.dart`, `lib/core/settings.dart` |
| English and Czech interface | `lib/ui/strings.dart` |
| OS secure storage | `lib/core/settings.dart` |
| Android foreground service, no boot receiver | `android/app/src/main/AndroidManifest.xml` |
| Hardware, Tailscale and desktop requirements | `README.md`, `docs/setup.html` |
| Public policy and support contact | `docs/privacy.html`, `docs/support.html` |

## Separate Console requirements

Listing text does not complete app access, Data safety, target audience, content rating, foreground-service declarations, testing eligibility or production review. Use the current Console state and the actual uploaded version. See [the existing disclosure guidance](../play-console.md).

App access instructions must explain the separate Tailscale account, User and Waker devices, and compatible target hardware. Do not claim unrestricted reviewer access or supply invented credentials. A packet-only demonstration must not claim a real PC boot.

Data safety needs a separate decision under Google's definitions for user-directed peer transfers. This copy does not declare an exemption or describe local Wake-on-LAN broadcasts as encrypted. Target ages express the publisher's intended audience and cannot be inferred from source code. Content-rating agreements and any new legal agreements need the required human acceptance.

Feature graphics, real-device screenshots and any required foreground-service demonstration video still need their own review. Do not substitute generated screens for evidence of app behavior. Do not publish a new app release or claim public Google Play availability from these metadata files.
