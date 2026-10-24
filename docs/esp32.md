# ESP32 companion Waker

This experimental firmware turns a Wi-Fi ESP32 into a local Wake-on-LAN relay.
It is separate from the Flutter app and Go CLI. It does not support AVR Uno,
Nano, or every board sold under the Arduino name. No ESP32 hardware is attached
to the development computer, so flashing and on-board execution remain unverified.

## Choose the right device

An awake Windows/Linux laptop or Raspberry Pi can run the [Go CLI](cli.md)
directly. That is the shorter setup. The ESP32 cannot run Tailscale itself.
It still needs an awake Tailscale gateway on the same physical LAN.

The route is:

```text
User app or CLI | encrypted Tailscale connection
Gateway TCP 45879 | forwards to ESP32 LAN IPv4, TCP 45879
ESP32 | authenticates request, sends fixed-target UDP magic packet
Target PC | must support and enable Ethernet WOL or Wi-Fi WoWLAN
```

Pair the User with the gateway's `100.64.0.0/10` IPv4. Do not pair with the
ESP32's `192.168.x.x` address. Reserve the ESP32's LAN address in your router.
Do not forward this service from the public internet or use Tailscale Funnel.

## Build and flash

The license permits personal builds of the unmodified official firmware for
your own devices. Other new source builds need the permission described in
[LICENSE](../LICENSE). Dependencies retain their own licenses.

Use Arduino CLI 1.5.1 and ESP32 Arduino core 3.3.12. Install them from the
[Arduino CLI project](https://arduino.github.io/arduino-cli/) and
[Espressif's official instructions](https://docs.espressif.com/projects/arduino-esp32/en/latest/installing.html).
The following board target is the generic ESP32 Dev Module. Confirm the exact
board, flash size, USB port and voltage before uploading.

```sh
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32@3.3.12 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli compile --fqbn esp32:esp32:esp32 firmware/esp32
arduino-cli board list
```

After selecting the board's actual port, replace `YOUR_PORT`:

```sh
arduino-cli upload --port YOUR_PORT --fqbn esp32:esp32:esp32 firmware/esp32
arduino-cli monitor --port YOUR_PORT --config baudrate=115200
```

Uploading replaces the board's current firmware. Releases distribute original
source, not a linked ESP32 binary. Rebuilding also downloads third-party code
under its own terms, including the Arduino core's LGPL obligations.

## Configure through USB serial

Use 115200 baud, 8N1 and newline. The firmware has no Wi-Fi setup portal or
remote configuration endpoint. Example values must be replaced with your own:

```text
set-wifi "Home WiFi" "your Wi-Fi password"
set-target 02:11:22:33:44:55
set-gateway 100.101.102.103
set-name "Home Waker"
gen-key
status
test-wake
pair
```

Quotes allow spaces. Literal double quotes inside an argument are unsupported.
An open network can omit the password. Serial lines must fit in 255 bytes.
Overlong lines are discarded in full. Pairing output contains the secret key;
keep serial logs, screenshots and terminal history private.

| Command | Result |
| --- | --- |
| `help` | Show commands. |
| `status` | Show Wi-Fi, clock and target state; hide the key. |
| `set-wifi <ssid> [password]` | Save Wi-Fi credentials and connect. |
| `set-target <mac>` | Save one nonzero unicast target MAC. |
| `set-gateway <tailnet-ip>` | Save the gateway's Tailscale IPv4. |
| `set-name <name>` | Save 1 to 80 printable ASCII characters. |
| `gen-key` | Generate and save a new 32-byte key. Re-pair every User. |
| `set-key <base64url-key>` | Import an existing canonical 32-byte key. |
| `pair` | Print a compatible private `seliawake://pair?data=...` URI. |
| `test-wake` | Send the configured local packet without Tailscale. |
| `reset` | Erase firmware settings from NVS and disconnect Wi-Fi. |
| `reboot` | Restart the board. |

## Connect the gateway

Configure a TCP proxy on the gateway, bound only to its assigned Tailscale IPv4
at port 45879, forwarding to the ESP32's LAN IPv4 at port 45879. Restrict access
with Tailscale policy and the gateway firewall. No gateway, firewall or startup
configuration is installed by this repository. Keep the proxy running.

On the User app, paste the URI from `pair`, check the displayed name and gateway
address, then save. The CLI imports the same URI with `seliawake pair --stdin`.
Press Wake or run `seliawake wake`. A successful response means UDP send
completed. It does not prove that the target PC booted.

## Security and limits

* Wi-Fi credentials and the pairing key are plaintext in ESP32 NVS. Flash
  encryption and secure boot are not configured. Protect physical and serial
  access. `reset` removes logical settings, not a forensic flash history.
* Tailscale encrypts User-to-gateway transport. Gateway-to-ESP32 HTTP and the
  local UDP broadcast are unencrypted. HMAC authenticates requests.
* Requests follow [protocol v1](protocol.md): fixed target, HMAC-SHA256,
  inclusive 30-second timestamp window, at most 128 cached nonces, and 30 valid
  requests per 60-second window. Nonces last at least 60 seconds and through
  their timestamp's final accepted second. Restart clears this memory.
* Headers and bodies each have a 1024-byte bound. One connection is processed
  at a time, with a 3000 ms total read deadline. Sustained reachable traffic
  can still deny service. There is no claim of internet-facing robustness.
* The board contacts `pool.ntp.org` and `time.nist.gov` for time. Requests fail
  until its clock is ready. Network isolation or bad time can prevent wakes.
* `protocol.h` contains the production JSON parser and replay-expiry helper.
  `firmware/tests/protocol_test.cpp` tests those same functions on a host C++
  compiler. Compilation and source review do not prove Wi-Fi, NVS, board
  timing, gateway forwarding, UDP delivery, or physical PC wake.

See [privacy](privacy.html), [verification](verification.md), and
[third-party notices](../THIRD_PARTY_NOTICES.md).
