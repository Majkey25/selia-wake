# Relay protocol v1

TCP port 45879. HTTP POST /v1/wake, Content-Type application/json. Body at most 1024 bytes. Fields: timestamp (integer Unix seconds), nonce (base64url without padding, 16 random bytes), signature (64 lowercase hexadecimal characters).

Secret: 32 random bytes, represented as unpadded base64url. Signature: HMAC-SHA256 with decoded secret, over UTF-8 of timestamp + newline + nonce + newline + wake-v1. Reject timestamps outside 30 seconds, nonce reuse for 60 seconds, incorrect signatures, incorrect shapes, oversized requests, invalid routes, and excess attempts. Replay store at most 128 entries. Constant-time comparison. Never log pairing secrets or signatures.

200 JSON {"status":"sent"} only after the configured target receives a successful UDP send call. Error responses use {"error":"invalid_request|unauthorized|expired|replay|rate_limited|wifi_unavailable|send_failed"}. Never accept target addresses or MACs from a remote request. No health endpoint exposing target details.

Magic packet: six 0xff bytes then sixteen copies of the six-byte target MAC. UDP port 9 on the physical LAN. Android selects Wi-Fi using NetworkCapabilities.TRANSPORT_WIFI and binds the socket to that network's IPv4 source address. Explicit Network.bindSocket can fail with EPERM under Android VPNs. Desktop also binds the LAN IPv4 source address. VPN policy must permit local LAN traffic. One target per Waker.

## Flutter Android interface

MethodChannel selia_wake/relay:

- start({mac:String,broadcast:String,secret:String,port:Int,name:String,language:String})
- stop()
- status() returns {running:bool,error:String?,port:Int}
- wakeLocal({mac:String,broadcast:String})
- networkInfo() returns {wifiIp:String?,broadcast:String?,tailscaleIp:String?}

No I/O on the platform UI thread. Start must report actual bind success or failure. Service persists independently of Activity; stop closes listeners, threads and locks. Persistent notification exposes a Stop action. No backup or automatic start at boot. Android minSdk26, targetSdk36.
