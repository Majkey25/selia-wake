# Relay protocol v1

TCP port 45879. HTTP POST /v1/wake, Content-Type application/json. Body at most 1024 bytes. Fields: timestamp (integer Unix seconds), nonce (base64url without padding, 16 random bytes), signature (64 lowercase hexadecimal characters).

Secret: 32 random bytes, represented as unpadded base64url. Signature: HMAC-SHA256 with decoded secret, over UTF-8 of timestamp + newline + nonce + newline + wake-v1. Reject timestamps outside the inclusive 30-second window, incorrect signatures, incorrect shapes, oversized requests, invalid routes, and excess attempts. Retain each nonce for at least 60 seconds and through its timestamp's final accepted second: expiry is max(acceptedAt + 60, timestamp + 31). Replay store at most 128 entries. Constant-time comparison. Never log pairing secrets or signatures.

Only authenticated, fresh, non-replayed requests consume the shared wake quota: 30 per 60 seconds on Android, 60 per 60 seconds on desktop. Connection, body, timeout, and replay-store bounds apply separately.

The desktop GUI admits at most eight TCP connections before HTTP parsing. Each
accepted connection has a five-second absolute lifetime, including incomplete
headers. Excess connections close immediately. The existing body timeout and
size limit still apply. Sustained hostile traffic can affect availability;
these bounds do not replace tailnet access controls or a firewall.

200 JSON {"status":"sent"} only after the configured target receives a successful UDP send call. Error responses use {"error":"invalid_request|unauthorized|expired|replay|rate_limited|wifi_unavailable|send_failed"}. Never accept target addresses or MACs from a remote request. No health endpoint exposing target details.

Magic packet: six 0xff bytes then sixteen copies of the six-byte target MAC. UDP port 9 on the physical LAN. Android selects Wi-Fi using NetworkCapabilities.TRANSPORT_WIFI and binds the socket to that network's IPv4 source address. Explicit Network.bindSocket can fail with EPERM under Android VPNs. Desktop also binds the LAN IPv4 source address. VPN policy must permit local LAN traffic. One target per Waker.

## Flutter Android interface

MethodChannel selia_wake/relay:

- start({mac:String,broadcast:String,secret:String,port:Int,name:String,language:String})
- stop()
- status() returns {running:bool,error:String?,port:Int}
- wakeLocal({mac:String,broadcast:String})
- networkInfo() returns {wifiIp:String?,broadcast:String?,tailscaleIp:String?}
- scanPairing({language:String}) returns the scanned pairing URI, or null on cancellation. Only en/cs are accepted. A denied camera permission returns camera_permission_denied. Decoded results are limited to 2048 characters and require Dart Pairing.parse validation. A valid explicit scan saves automatically in Settings.

No I/O on the platform UI thread. Start must report actual bind success or failure. Service persists independently of Activity; stop closes listeners, threads and locks. Persistent notification exposes a Stop action. No backup or automatic start at boot. Android minSdk26, targetSdk36.
