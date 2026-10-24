# Bounded security audit, 24 October 2026

Scope: Flutter pairing, configuration and HTTP relay; Android relay authentication, request parsing, service and QR boundary; manifest and privacy text. This is a source review with focused runtime checks, not a security certification or exhaustive penetration test.

## Confirmed finding and fix

**P2: unauthenticated traffic could consume the shared wake quota.** Android charged its 30-request quota before authentication. Desktop charged its 60-request quota before JSON/HMAC/replay validation. A reachable peer without the pairing key could temporarily deny legitimate wakes.

Both implementations now charge the shared quota only after validating the request, timestamp, HMAC, replay protection and replay-store capacity. Connection, body, timeout and memory bounds remain in place. The Dart regression test failed before the fix and passes afterward; valid authenticated requests still hit the configured limit.

On the physical Android Waker, a live test made 35 empty TCP connections, then 65 rounds each of malformed JSON, bad HMAC, expired timestamps and replayed nonces. Legitimate signed requests continued to work. The independent LAN receiver observed exactly 30 correct 102-byte magic packets, and the next valid request returned 429.

A second bounded, read-only source review by Codex 6.1 at extra-high reasoning found no remaining confirmed P1/P2 in the reviewed scope. The primary checked the advice against the diff and reproduced the protocol behavior separately. Reviewer agreement is not runtime proof.

## Version 0.2.0 protocol review

An independent CLI source review found a second P2: a request accepted at time T
with timestamp T+30 could replay at T+60. Its original 60-second nonce entry had
expired, but the timestamp still passed the inclusive 30-second freshness check.
Go, Dart and Android now retain it through the final accepted timestamp second,
with a minimum 60-second TTL. Regression tests reproduced the failure before
the fix and passed afterward. Android uses elapsed time for the retained entry.

A fresh source-snapshot review by GPT-6 Astra at extra-high reasoning found no
confirmed P1/P2 in the supplied CLI, Dart protocol and Android protocol scope.
The reviewer did not execute tests, verify file hashes, or inspect all service
callers. Primary verification included Go tests/vet, Dart protocol tests and
two Android JVM tests. This is bounded evidence, not a security certification.

The Go CLI binds only its configured Tailscale IPv4 and uses owner-only local
configuration, including a protected single-user Windows DACL. Its key remains
plaintext on disk. ESP32 companion firmware is a separate experimental scope
with plaintext NVS and an external Tailscale gateway requirement.

A separate source-snapshot review found no confirmed P1/P2 in the bounded
ESP32 firmware and shared C++ parser. Primary compiled the firmware with the
pinned Arduino core in a fresh isolated build. Flashing, NVS failure behavior,
live gateway interoperability and actual board execution remain unverified.

## Pairing and QR boundary

QR and copied links carry the same 32-byte pairing key. Scanning is an explicit Android action, requires camera permission, accepts QR only, limits decoded text to 2048 characters, then uses the existing Pairing.parse validator. Scanned name and host are shown before explicit Save. Cancelling does not persist the draft. Clipboard reads and writes require the corresponding user action.

The scanner activity is not exported. Barcode-image saving and the scan beep are disabled. The camera decodes locally through ZXing; the app does not upload or retain camera images. Denied permission returns an app error, and cancelling releases the camera. The reviewed native configuration stays in memory, while persistent pairing secrets use OS secure storage. Android backup is disabled.

## Remaining limits

The relay is reachable on network interfaces beyond Tailscale where the OS permits it. HMAC authorizes wake requests; Tailscale ACLs and the desktop firewall should restrict reachability. A pairing key grants the ability to wake the configured target. The app has no in-app key rotation control. Deleting a User pairing does not revoke another copy. Resetting Android Waker app data removes its configuration and generates a new key on next launch.

Bounded connection and request handling does not guarantee resistance to sustained resource exhaustion. Device compromise, stolen pairing keys, Tailscale account security, OS keyring failures, dependency supply-chain security and firmware vulnerabilities remain outside this bounded test. No claim is made that every dependency is vulnerability-free.

Camera permission denial, retry, open and cancellation were exercised on Android 10. Actual optical pairing from a second device, process-death/activity-recreation during scanning, newer Android permission behavior, long-duration background availability, Linux GUI runtime and physical PC wake were not verified.
