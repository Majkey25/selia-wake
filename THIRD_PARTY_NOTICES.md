# Third-party notices

The proprietary license covers original Selia Wake material. It does not
replace dependency licenses or restrict rights granted by their authors.

* IBM Plex Mono: SIL Open Font License 1.1, [bundled license](assets/fonts/OFL.txt).
* Flutter and Dart: BSD-style licenses. Desktop and Android bundles include
  Flutter's generated third-party notices.
* Dart dependencies: exact versions are recorded in `pubspec.lock`. Their
  license texts are included in Flutter's generated license registry.
* ZXing Android Embedded and ZXing Core: Apache License 2.0. Android dependency
  versions are recorded in `android/app/build.gradle.kts`.
* Go: BSD-style license. Standalone CLI archives include the Go toolchain's
  `LICENSE` and `PATENTS` notices for the linked runtime and standard library.
* ESP32 Arduino core, including its Wi-Fi/network libraries: LGPL 2.1 or later.
  ESP-IDF components have their own licenses, including Apache 2.0 components.
  The companion is distributed as original source for personal builds, without
  bundling these libraries or a linked firmware binary. Obtain the pinned core
  from Espressif and retain its license files. Redistribution of a linked build
  requires complying with all linked component licenses and the applicable
  relinking/source obligations.

Tailscale is installed separately and is not included in these binaries.
Third-party names and trademarks remain the property of their owners.
