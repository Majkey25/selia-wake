# Bounded security audit

Scope: Flutter pairing, configuration and HTTP relay; Android relay authentication, request parsing, service and QR boundary; manifest and privacy text. This is a source review with focused runtime checks, not a security certification or exhaustive penetration test.

## 0.3.1 desktop setup security update

A renewed Astra review confirmed an approval-dependent local P1 in 0.3.0:
desktop setup could elevate a temporary script writable by the invoking user.
Another process under that same account could replace the source before the
privileged interpreter loaded it. A private directory did not prevent
same-user replacement. No remote exploit was established.

Automatic elevation has been removed. Sleeper never requests UAC or polkit
approval, runs pkexec, or elevates temporary scripts. Inspection and permitted
setters use the existing process token. Permission failures direct users to
separate native OS configuration, preserving uncertainty about partial changes.
Do not run the whole app as administrator or root. This closes the reported
privilege transition without adding an installed privileged helper.

The review also identified a P2: a fresh Windows inspection discarded a known
pending restart advisory. Valid reports now retain that advisory by GUID and
canonical MAC across backend instances in the same process, including partial
failure reports. History is bounded to 128 entries; eviction or a new process
means unknown activation. Stored Magic Packet configuration never establishes
that the driver activated it. The UI labels the setting and advisory accordingly.
The operation also returns its validated original identity independently of
current adapter enumeration, so disappearance after a successful setter does
not erase the advisory. Both disappearance regressions failed before that fix.
A final Astra max source review confirmed both findings closed, with no new
confirmed P1/P2 in the supplied scope. It did not independently rerun tests or
verify privileged mutation, driver activation or hardware wake.

Primary verification passed all 107 Flutter tests and analysis. Windows
PowerShell fixtures cover ordinary-token setters, idempotence, denial and
partial changes without changing real adapters. Live ordinary Windows
inspection and an already-configured Enable operation passed on this PC.
Nine additional real-loopback network probes passed, including body deadlines,
slot recovery, restart with a changed key, bind conflict and send failure.
Their UDP operation was mocked; they do not establish hardware wake.

An [OSV advisory lookup](https://google.github.io/osv.dev/post-v1-querybatch/)
returned no matches for 145 exact public package/version coordinates from the
resolved Pub graph, Android release runtime graph and Go 1.27.3 standard
library. This checks known records, not exploit reachability or all SDK,
native-binary, firmware and supply-chain risks. Dependency versions were not
changed. The earlier 0.3.0 release notes now warn against its automatic elevation.

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

Version 0.3.0 updates this flow at the user's request: valid explicit Paste or
Scan actions save automatically. Revert restores the opening settings while
the page remains open. Reset defaults clears connections and rotates the
Waker key; Revert during that visit can restore the previous key. The earlier
explicit-Save and no-rotation descriptions below record version 0.2.0.

The 25 October source review found and closed two autosave races: consecutive
saves comparing against a widget awaiting rebuild, and a delayed clipboard
result restoring pairing after Reset. The parent now tracks successful writes
immediately, and Paste rejects results after newer edits. Independent follow-up
review found no remaining confirmed P1/P2 in its supplied snapshot. Primary ran
all 89 Flutter tests; the reviewer did not independently execute them.

QR and copied links carry the same 32-byte pairing key. Scanning is an explicit Android action, requires camera permission, accepts QR only, limits decoded text to 2048 characters, then uses the existing Pairing.parse validator. Scanned name and host are shown before explicit Save. Cancelling does not persist the draft. Clipboard reads and writes require the corresponding user action.

The scanner activity is not exported. Barcode-image saving and the scan beep are disabled. The camera decodes locally through ZXing; the app does not upload or retain camera images. Denied permission returns an app error, and cancelling releases the camera. The reviewed native configuration stays in memory, while persistent pairing secrets use OS secure storage. Android backup is disabled.

## Remaining limits

### 25 October 2026 connection review

MajkeyLab Astra max independently identified a P2 in the desktop GUI: its
eight-request cap ran after headers, leaving incomplete TCP/HTTP connections
outside that count. A real loopback probe retained 24 such connections after
six seconds. Two regression tests failed before the fix.

The desktop listener now bounds accepted TCP connections before HTTP parsing
and closes each after at most five seconds. Excess connections close
immediately. Completed sockets are pruned before accepting another, and stop
closes both the HTTP server and its owned socket listener. Three real-socket
tests cover connection capacity, absolute lifetime, and valid authentication
after 65 malformed requests. The complete 92-test suite and analysis passed.
A second source review confirmed the reported issue was addressed and found
no new P1/P2 within the supplied implementation. It did not independently
execute the tests or certify the application.

On the physical Android Waker, a fresh test made 35 unauthenticated connections,
then tried wrong HMAC, malformed JSON, an extra target MAC, oversized bodies,
queries, expired/future timestamps and replay. All were rejected without UDP
delivery. Oversized and invalid-route requests could close with a TCP reset
instead of an HTTP response. Two valid signed requests each delivered the exact
configured packet. A physical LAN client without the key received HTTP 401.
No pairing key or QR image was saved in evidence. The PC stayed awake.

The GUI listener can be reachable on the physical LAN as well as Tailscale.
HMAC authenticates requests; it does not encrypt that LAN endpoint. Tailscale
encrypts traffic carried through its VPN. Its default tailnet policy can allow
all peers, so restrict access to intended User devices on TCP 45879. Grants
are additive: a narrow grant does not cancel an existing broad allowance.
No router, firewall, Funnel, RDP authentication or tailnet policy was changed
by this app. See [Tailscale access control](https://tailscale.com/docs/reference/syntax/grants)
and [connection encryption](https://tailscale.com/docs/reference/connection-types).

Standard LAN magic packets are unencrypted and do not authenticate the sender.
A trusted LAN is still required. Wake does not grant OS login or shell access.
The Sleeper role does not start a Waker listener or accept privileged network
commands. These checks do not establish that every dependency, OS, firmware,
network policy or deployment is free of vulnerabilities.

### Earlier deployment limits

The relay is reachable on network interfaces beyond Tailscale where the OS permits it. HMAC authorizes wake requests; Tailscale ACLs and the desktop firewall should restrict reachability. A pairing key grants the ability to wake the configured target. Reset defaults rotates the Waker key and clears connections. Deleting a User pairing does not revoke another copy. Revert changes can restore the prior key during the same Settings visit.

Bounded connection and request handling does not guarantee resistance to sustained resource exhaustion. Device compromise, stolen pairing keys, Tailscale account security, OS keyring failures, dependency supply-chain security and firmware vulnerabilities remain outside this bounded test. No claim is made that every dependency is vulnerability-free.

Camera permission denial, retry, open and cancellation were exercised on Android 10. Actual optical pairing from a second device, process-death/activity-recreation during scanning, newer Android permission behavior, long-duration background availability, Linux GUI runtime and physical PC wake were not verified.
