# Publish a release

This is the maintainer checklist. Never replace historical release assets with newer builds.

1. Set the Flutter version and Android version code in `pubspec.yaml`. Use a new `vX.Y.Z` tag. Keep test builds marked as prereleases.
2. Run Flutter analysis and tests, Go tests and vet on Windows and Linux, and the CLI race test on Linux. Review protocol, storage and platform changes. Record checks and untested hardware in `verification.md`.
3. Build signed Android APK and AAB locally using the private upload keystore. Keep signing files outside Git. Verify the signing certificate, APK alignment and AAB validation. Never substitute a debug key.
4. Push the reviewed commit. Wait for all jobs in `build.yml`. Download the GUI and CLI artifacts from that exact commit's successful workflow. Cross-builds do not prove ARM hardware execution.
5. Create a draft GitHub prerelease with these assets:

   * `selia-wake-android.apk`
   * `selia-wake-windows-x64.zip`
   * `selia-wake-linux-x64.tar.gz`
   * `selia-wake-cli-windows-x64.zip`
   * `selia-wake-cli-linux-x64.tar.gz`
   * `selia-wake-cli-linux-arm64.tar.gz`
   * `selia-wake-cli-linux-armv7.tar.gz`
   * `SHA256SUMS`

6. Include the current license, historical MIT notice and third-party notices in archives. CLI archives also include the linked Go runtime's `LICENSE` and `PATENTS`. Add companion firmware separately with its board identifier, build instructions and explicit hardware-test status.
7. Write installation instructions for Android, Windows, Linux and CLI in the release notes. Link the setup, privacy and CLI guides. State minimum versions, known dependencies and untested platforms. Never describe a successful packet send as a successful hardware wake.
8. Calculate SHA-256 from the exact files being uploaded. Read back the asset list, sizes and server digests before publishing. Publish only after all required installation packages exist.
9. Upload the matching signed AAB only to Google Play internal testing. Confirm the new version is available to the selected internal testers. A GitHub release or successful upload does not prove Play availability. Production publication requires separate authorization.

CI generates tested desktop and CLI artifacts. It does not hold the Android signing key, publish incomplete releases or modify already-published assets. Android publication and final draft release publication remain deliberate maintainer actions.
