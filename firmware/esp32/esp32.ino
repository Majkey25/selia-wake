#include <Arduino.h>
#include <WiFi.h>
#include <WiFiServer.h>
#include <WiFiClient.h>
#include <WiFiUdp.h>
#include <Preferences.h>
#include <time.h>
#include <esp_system.h>
#include "mbedtls/md.h"
#include "protocol.h"

// ============================================================================
// Protocol & Firmware Constants
// ============================================================================
static const uint16_t RELAY_PORT              = 45879;
static const uint16_t WOL_PORT                = 9;
static const size_t   MAX_HEADER_SIZE         = 1024;
static const size_t   MAX_NONCES              = 128;
static const int      RATE_LIMIT_QUOTA        = 30;
static const int      RATE_LIMIT_WINDOW_SEC   = 60;
static const unsigned long SOCKET_TIMEOUT_MS  = 3000;
static const size_t   SERIAL_BUF_SIZE         = 256;
static const char*    NVS_NAMESPACE           = "waker";

// ============================================================================
// Data Structures (Defined early for Arduino auto-prototyping)
// ============================================================================
struct NonceEntry {
    char nonce[23]; // 22 base64url chars + '\0'
    time_t expiry;
};


static NonceEntry s_nonces[MAX_NONCES];
static size_t     s_nonce_count = 0;

static time_t     s_rate_window = 0;
static int        s_rate_attempts = 0;

// ============================================================================
// Configuration State (backed by NVS Preferences)
// ============================================================================
static Preferences s_prefs;
static String      s_wifi_ssid     = "";
static String      s_wifi_pass     = "";
static uint8_t     s_target_mac[6] = {0};
static bool        s_target_mac_set= false;
static String      s_gateway_ip    = "";
static String      s_device_name   = "";
static String      s_secret_key    = ""; // 43 chars base64url (32 bytes)
static uint8_t     s_secret_bytes[32];
static bool        s_secret_set    = false;

// Hardware & Networking
static WiFiServer  s_server(RELAY_PORT);
static WiFiUDP     s_udp;
static unsigned long s_last_wifi_check = 0;

// Serial Line Reader State
static char        s_serial_buf[SERIAL_BUF_SIZE];
static size_t      s_serial_pos = 0;
static bool        s_serial_overflow = false;

// ============================================================================
// Base64url and Cryptographic Utilities
// ============================================================================

static inline int base64UrlVal(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '-') return 62;
    if (c == '_') return 63;
    return -1;
}

static const char B64URL_TABLE[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

static bool decodeBase64Url32(const String& input, uint8_t out32[32]) {
    if (input.length() != 43) return false;
    for (int i = 0; i < 43; i++) {
        if (!isBase64UrlChar(input.charAt(i))) return false;
    }

    uint32_t buffer = 0;
    int bits_collected = 0;
    size_t out_idx = 0;

    for (int i = 0; i < 43; i++) {
        int v = base64UrlVal(input.charAt(i));
        if (v < 0) return false;
        buffer = (buffer << 6) | (uint32_t)v;
        bits_collected += 6;
        if (bits_collected >= 8) {
            bits_collected -= 8;
            if (out_idx < 32) {
                out32[out_idx++] = (uint8_t)((buffer >> bits_collected) & 0xFF);
            }
        }
    }

    if (out_idx != 32) return false;
    if ((buffer & ((1 << bits_collected) - 1)) != 0) return false;
    return true;
}

static String encodeBase64Url(const uint8_t* data, size_t len) {
    String out = "";
    out.reserve(((len + 2) / 3) * 4);

    uint32_t buffer = 0;
    int bits = 0;
    for (size_t i = 0; i < len; i++) {
        buffer = (buffer << 8) | data[i];
        bits += 8;
        while (bits >= 6) {
            bits -= 6;
            out += B64URL_TABLE[(buffer >> bits) & 0x3F];
        }
    }
    if (bits > 0) {
        out += B64URL_TABLE[(buffer << (6 - bits)) & 0x3F];
    }
    return out;
}

static bool constantTimeEquals(const char* a, size_t a_len, const char* b, size_t b_len) {
    size_t max_len = (a_len > b_len) ? a_len : b_len;
    int diff = (int)(a_len ^ b_len);
    for (size_t i = 0; i < max_len; i++) {
        char ca = (i < a_len) ? a[i] : 0;
        char cb = (i < b_len) ? b[i] : 0;
        diff |= (ca ^ cb);
    }
    return diff == 0;
}

static bool computeHmacSha256Hex(const uint8_t* key, size_t key_len,
                                 const uint8_t* data, size_t data_len,
                                 char out_hex[65]) {
    uint8_t hmac_buf[32];
    const mbedtls_md_info_t* md_info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    if (!md_info) return false;

    int ret = mbedtls_md_hmac(md_info, key, key_len, data, data_len, hmac_buf);
    if (ret != 0) return false;

    for (int i = 0; i < 32; i++) {
        snprintf(&out_hex[i * 2], 3, "%02x", hmac_buf[i]);
    }
    out_hex[64] = '\0';
    return true;
}

// ============================================================================
// Configuration & Preferences Management
// ============================================================================

static void loadSettings() {
    s_prefs.begin(NVS_NAMESPACE, true);
    s_wifi_ssid      = s_prefs.getString("wifi_ssid", "");
    s_wifi_pass      = s_prefs.getString("wifi_pass", "");
    s_gateway_ip     = s_prefs.getString("gateway_ip", "");
    s_device_name    = s_prefs.getString("dev_name", "");
    s_secret_key     = s_prefs.getString("secret_key", "");

    size_t mac_len = s_prefs.getBytes("target_mac", s_target_mac, 6);
    s_target_mac_set = (mac_len == 6);

    s_prefs.end();

    if (s_secret_key.length() == 43) {
        s_secret_set = decodeBase64Url32(s_secret_key, s_secret_bytes);
    } else {
        s_secret_set = false;
    }
}

static bool parseMac(const char* str, uint8_t mac_out[6]) {
    if (strlen(str) != 17) return false;
    int values[6];
    char sep = str[2];
    if (sep != ':' && sep != '-') return false;

    for (int i = 0; i < 6; i++) {
        char byte_str[3] = { str[i * 3], str[i * 3 + 1], '\0' };
        char* endptr = nullptr;
        long val = strtol(byte_str, &endptr, 16);
        if (*endptr != '\0' || val < 0 || val > 255) return false;
        values[i] = (int)val;
        if (i < 5 && str[i * 3 + 2] != sep) return false;
    }

    if ((values[0] & 1) != 0) return false; // multicast bit
    bool all_zero = true;
    for (int i = 0; i < 6; i++) {
        if (values[i] != 0) { all_zero = false; break; }
    }
    if (all_zero) return false;

    for (int i = 0; i < 6; i++) mac_out[i] = (uint8_t)values[i];
    return true;
}

static bool isTailnetAddress(const char* str) {
    IPAddress ip;
    if (!ip.fromString(str)) return false;
    return (ip[0] == 100 && ip[1] >= 64 && ip[1] <= 127);
}

static bool isClockReady() {
    time_t now = time(nullptr);
    return now > 1700000000;
}

static bool isValidDeviceName(const String& name) {
    if (name.length() < 1 || name.length() > 80) return false;
    for (size_t i = 0; i < name.length(); i++) {
        char c = name.charAt(i);
        if ((uint8_t)c < 0x20 || (uint8_t)c > 0x7E) return false;
    }
    return true;
}

static String escapeJsonString(const String& input) {
    String out = "";
    out.reserve(input.length() + 16);
    for (size_t i = 0; i < input.length(); i++) {
        char c = input.charAt(i);
        if (c == '"') {
            out += "\\\"";
        } else if (c == '\\') {
            out += "\\\\";
        } else if (c == '\b') {
            out += "\\b";
        } else if (c == '\f') {
            out += "\\f";
        } else if (c == '\n') {
            out += "\\n";
        } else if (c == '\r') {
            out += "\\r";
        } else if (c == '\t') {
            out += "\\t";
        } else if ((uint8_t)c < 0x20) {
            char ubuf[7];
            snprintf(ubuf, sizeof(ubuf), "\\u%04x", (uint8_t)c);
            out += ubuf;
        } else {
            out += c;
        }
    }
    return out;
}

// ============================================================================
// Strict JSON & Protocol Parsing
// ============================================================================

// ============================================================================
// Nonce Replay & Rate Limiter
// ============================================================================

static void purgeExpiredNonces(time_t now) {
    size_t write_idx = 0;
    for (size_t i = 0; i < s_nonce_count; i++) {
        if (s_nonces[i].expiry > now) {
            if (write_idx != i) {
                s_nonces[write_idx] = s_nonces[i];
            }
            write_idx++;
        }
    }
    s_nonce_count = write_idx;
}

static bool isNonceReplayed(const char* nonce) {
    for (size_t i = 0; i < s_nonce_count; i++) {
        if (strcmp(s_nonces[i].nonce, nonce) == 0) {
            return true;
        }
    }
    return false;
}

static bool storeNonce(const char* nonce, time_t expiry) {
    if (s_nonce_count >= MAX_NONCES) return false;
    strncpy(s_nonces[s_nonce_count].nonce, nonce, 22);
    s_nonces[s_nonce_count].nonce[22] = '\0';
    s_nonces[s_nonce_count].expiry = expiry;
    s_nonce_count++;
    return true;
}

// ============================================================================
// WOL Packet Transmission
// ============================================================================

static bool sendMagicPacket() {
    if (!s_target_mac_set) return false;
    if (WiFi.status() != WL_CONNECTED) return false;

    uint8_t packet[102];
    memset(packet, 0xFF, 6);
    for (int i = 0; i < 16; i++) {
        memcpy(&packet[6 + i * 6], s_target_mac, 6);
    }

    if (!s_udp.beginPacket(IPAddress(255, 255, 255, 255), WOL_PORT)) {
        return false;
    }
    size_t written = s_udp.write(packet, 102);
    if (written != 102) {
        return false;
    }
    return (s_udp.endPacket() == 1);
}

// ============================================================================
// Minimal Bounded HTTP Server Implementation
// ============================================================================

static void sendHttpResponse(WiFiClient& client, int code, const char* status_text, const char* json_body) {
    client.print("HTTP/1.1 ");
    client.print(code);
    client.print(" ");
    client.println(status_text);
    client.println("Content-Type: application/json");
    client.println("Connection: close");
    client.print("Content-Length: ");
    client.println(strlen(json_body));
    client.println();
    client.print(json_body);
    client.flush();
}

static void sendErrorResponse(WiFiClient& client, int code, const char* err_code) {
    char buf[64];
    snprintf(buf, sizeof(buf), "{\"error\":\"%s\"}", err_code);
    const char* phrase = "Error";
    if (code == 400) phrase = "Bad Request";
    else if (code == 401) phrase = "Unauthorized";
    else if (code == 404) phrase = "Not Found";
    else if (code == 405) phrase = "Method Not Allowed";
    else if (code == 409) phrase = "Conflict";
    else if (code == 411) phrase = "Length Required";
    else if (code == 413) phrase = "Payload Too Large";
    else if (code == 415) phrase = "Unsupported Media Type";
    else if (code == 429) phrase = "Too Many Requests";
    else if (code == 431) phrase = "Request Header Fields Too Large";
    else if (code == 500) phrase = "Internal Server Error";
    else if (code == 503) phrase = "Service Unavailable";
    sendHttpResponse(client, code, phrase, buf);
}

static bool ciStartsWith(const char* str, const char* prefix) {
    while (*prefix) {
        if (tolower((unsigned char)*str) != tolower((unsigned char)*prefix)) return false;
        str++;
        prefix++;
    }
    return true;
}

static void handleHttpClient(WiFiClient client) {
    const unsigned long started = millis();

    char header_buf[MAX_HEADER_SIZE];
    size_t header_len = 0;
    bool headers_complete = false;

    // Read headers byte-by-byte bounded by MAX_HEADER_SIZE
    while (millis() - started < SOCKET_TIMEOUT_MS && client.connected()) {
        while (client.available()) {
            char c = (char)client.read();
            if (header_len + 1 >= MAX_HEADER_SIZE) {
                // Header fields too large
                sendErrorResponse(client, 431, "invalid_request");
                client.stop();
                return;
            }
            header_buf[header_len++] = c;

            // Check for end of headers: \r\n\r\n or \n\n
            if (header_len >= 4 &&
                header_buf[header_len - 4] == '\r' && header_buf[header_len - 3] == '\n' &&
                header_buf[header_len - 2] == '\r' && header_buf[header_len - 1] == '\n') {
                headers_complete = true;
                break;
            }
            if (header_len >= 2 &&
                header_buf[header_len - 2] == '\n' && header_buf[header_len - 1] == '\n') {
                headers_complete = true;
                break;
            }
        }
        if (headers_complete) break;
        delay(1);
    }

    if (!headers_complete) {
        client.stop();
        return;
    }
    header_buf[header_len] = '\0';

    // Parse Request Line
    char* line_end = strchr(header_buf, '\n');
    if (!line_end) {
        sendErrorResponse(client, 400, "invalid_request");
        client.stop();
        return;
    }
    *line_end = '\0';
    if (line_end > header_buf && *(line_end - 1) == '\r') {
        *(line_end - 1) = '\0';
    }

    char* method = header_buf;
    char* p = strchr(method, ' ');
    if (!p) {
        sendErrorResponse(client, 400, "invalid_request");
        client.stop();
        return;
    }
    *p = '\0';
    char* target_uri = p + 1;
    p = strchr(target_uri, ' ');
    if (!p) {
        sendErrorResponse(client, 400, "invalid_request");
        client.stop();
        return;
    }
    *p = '\0';
    char* http_ver = p + 1;

    // Verify HTTP method: only POST is allowed
    if (strcmp(method, "POST") != 0) {
        sendErrorResponse(client, 405, "invalid_request");
        client.stop();
        return;
    }

    // Verify exact route: must be exactly "/v1/wake" with no query string
    if (strcmp(target_uri, "/v1/wake") != 0) {
        sendErrorResponse(client, 404, "invalid_request");
        client.stop();
        return;
    }

    // Verify HTTP protocol version
    if (strcmp(http_ver, "HTTP/1.1") != 0 && strcmp(http_ver, "HTTP/1.0") != 0) {
        sendErrorResponse(client, 400, "invalid_request");
        client.stop();
        return;
    }

    // Parse Headers
    char* cur = line_end + 1;
    int content_length = -1;
    int cl_count = 0;
    int ct_count = 0;
    bool has_json_ct = false;
    bool has_chunked = false;

    while (cur < header_buf + header_len && *cur != '\0') {
        char* next_line = strchr(cur, '\n');
        if (!next_line) break;
        *next_line = '\0';
        char* next_cur = next_line + 1;
        if (next_line > cur && *(next_line - 1) == '\r') {
            *(next_line - 1) = '\0';
        }

        if (strlen(cur) == 0) {
            // Reached empty header line
            break;
        }

        if (ciStartsWith(cur, "content-length:")) {
            cl_count++;
            char* val = cur + 15;
            while (*val == ' ') val++;
            if (*val == '\0' || !isdigit((unsigned char)*val)) {
                sendErrorResponse(client, 400, "invalid_request");
                client.stop();
                return;
            }
            char* endptr = nullptr;
            long cl = strtol(val, &endptr, 10);
            while (endptr && *endptr == ' ') endptr++;
            if (*endptr != '\0' || cl < 0) {
                sendErrorResponse(client, 400, "invalid_request");
                client.stop();
                return;
            }
            content_length = (int)cl;
        } else if (ciStartsWith(cur, "content-type:")) {
            ct_count++;
            char* val = cur + 13;
            while (*val == ' ') val++;
            if (strcasecmp(val, "application/json") == 0 ||
                strcasecmp(val, "application/json; charset=utf-8") == 0) {
                has_json_ct = true;
            }
        } else if (ciStartsWith(cur, "transfer-encoding:")) {
            // Reject chunking / framing ambiguity
            has_chunked = true;
        }

        cur = next_cur;
    }

    if (has_chunked || cl_count > 1 || ct_count > 1) {
        sendErrorResponse(client, 400, "invalid_request");
        client.stop();
        return;
    }

    if (cl_count != 1 || content_length < 0) {
        sendErrorResponse(client, 411, "invalid_request");
        client.stop();
        return;
    }

    if (content_length == 0) {
        sendErrorResponse(client, 400, "invalid_request");
        client.stop();
        return;
    }

    if (content_length > (int)MAX_BODY_SIZE) {
        sendErrorResponse(client, 413, "invalid_request");
        client.stop();
        return;
    }

    if (!has_json_ct) {
        sendErrorResponse(client, 415, "invalid_request");
        client.stop();
        return;
    }

    // Read exact bounded body into fixed static buffer
    char body_buf[MAX_BODY_SIZE + 1];
    size_t body_read = 0;
    while (millis() - started < SOCKET_TIMEOUT_MS && client.connected() && body_read < (size_t)content_length) {
        while (client.available() && body_read < (size_t)content_length) {
            body_buf[body_read++] = (char)client.read();
        }
        if (body_read < (size_t)content_length) {
            delay(1);
        }
    }

    if (body_read != (size_t)content_length) {
        client.stop();
        return;
    }
    body_buf[body_read] = '\0';

    // Parse JSON
    WakeRequest req;
    if (!parseWakeJson(body_buf, body_read, req)) {
        sendErrorResponse(client, 400, "invalid_request");
        client.stop();
        return;
    }

    // Check system clock readiness
    if (!isClockReady()) {
        sendErrorResponse(client, 503, "clock_not_ready");
        client.stop();
        return;
    }

    time_t now = time(nullptr);

    // Timestamp window check: ±30 seconds
    int64_t diff = req.timestamp - (int64_t)now;
    if (diff < -FRESHNESS_SEC || diff > FRESHNESS_SEC) {
        sendErrorResponse(client, 401, "expired");
        client.stop();
        return;
    }

    // Key check
    if (!s_secret_set) {
        sendErrorResponse(client, 401, "unauthorized");
        client.stop();
        return;
    }

    // Canonical HMAC payload: "<timestamp>\n<nonce>\nwake-v1"
    char sign_payload[64];
    snprintf(sign_payload, sizeof(sign_payload), "%lld\n%s\nwake-v1",
             (long long)req.timestamp, req.nonce);

    char expected_sig[65];
    if (!computeHmacSha256Hex(s_secret_bytes, 32,
                              (const uint8_t*)sign_payload, strlen(sign_payload),
                              expected_sig)) {
        sendErrorResponse(client, 500, "send_failed");
        client.stop();
        return;
    }

    if (!constantTimeEquals(expected_sig, 64, req.signature, 64)) {
        sendErrorResponse(client, 401, "unauthorized");
        client.stop();
        return;
    }

    // Replay check
    purgeExpiredNonces(now);
    if (isNonceReplayed(req.nonce)) {
        sendErrorResponse(client, 409, "replay");
        client.stop();
        return;
    }

    // Replay store capacity check
    if (s_nonce_count >= MAX_NONCES) {
        sendErrorResponse(client, 429, "rate_limited");
        client.stop();
        return;
    }

    // Fixed 60-second window quota: 30 requests per 60s
    // ONLY authenticated, fresh, non-replayed requests consume this quota
    if (now - s_rate_window >= RATE_LIMIT_WINDOW_SEC || now < s_rate_window) {
        s_rate_window = now;
        s_rate_attempts = 0;
    }

    if (s_rate_attempts >= RATE_LIMIT_QUOTA) {
        sendErrorResponse(client, 429, "rate_limited");
        client.stop();
        return;
    }

    // Commit quota and record nonce
    s_rate_attempts++;
    time_t nonce_expiry = (time_t)nonceExpiry(now, req.timestamp);
    storeNonce(req.nonce, nonce_expiry);

    // Target configuration check
    if (!s_target_mac_set) {
        sendErrorResponse(client, 500, "send_failed");
        client.stop();
        return;
    }

    // Physical Wi-Fi connectivity check
    if (WiFi.status() != WL_CONNECTED) {
        sendErrorResponse(client, 503, "wifi_unavailable");
        client.stop();
        return;
    }

    // Broadcast UDP magic packet to UDP port 9 on physical LAN
    if (!sendMagicPacket()) {
        sendErrorResponse(client, 500, "send_failed");
        client.stop();
        return;
    }

    sendHttpResponse(client, 200, "OK", "{\"status\":\"sent\"}");
    client.stop();
}

// ============================================================================
// USB Serial CLI Handling
// ============================================================================

static void printHelp() {
    Serial.println();
    Serial.println("Selia Waker ESP32 - Interactive Commands:");
    Serial.println("  help                                - Show this command reference");
    Serial.println("  status                              - Show system, network, clock and target status");
    Serial.println("  set-wifi <ssid> [password]          - Configure Wi-Fi credentials (supports \"quotes\")");
    Serial.println("  set-target <mac>                    - Configure target MAC (e.g. AA:BB:CC:DD:EE:FF)");
    Serial.println("  set-gateway <tailnet-ip>            - Configure Tailscale gateway IP (100.64.0.0/10)");
    Serial.println("  set-name <name>                     - Configure device display name (1-80 chars)");
    Serial.println("  set-key <base64url-key>             - Set 32-byte secret key (43 unpadded base64url chars)");
    Serial.println("  gen-key                             - Generate random 32-byte secret key");
    Serial.println("  pair                                - Export pairing URI for mobile/desktop client");
    Serial.println("  test-wake                           - Trigger test WOL magic packet to target MAC");
    Serial.println("  reset                               - Wipe all stored settings (factory reset)");
    Serial.println("  reboot                              - Restart ESP32");
    Serial.println();
}

static void printStatus() {
    Serial.println();
    Serial.println("--- Selia Waker ESP32 Status ---");
    Serial.print("Wi-Fi SSID:       ");
    Serial.println(s_wifi_ssid.length() > 0 ? s_wifi_ssid : "(none configured)");

    Serial.print("Wi-Fi Status:     ");
    if (WiFi.status() == WL_CONNECTED) {
        Serial.print("Connected (IP: ");
        Serial.print(WiFi.localIP());
        Serial.print(", RSSI: ");
        Serial.print(WiFi.RSSI());
        Serial.println(" dBm)");
    } else {
        Serial.println("Disconnected");
    }

    Serial.print("System Clock:     ");
    if (isClockReady()) {
        time_t now = time(nullptr);
        struct tm timeinfo;
        gmtime_r(&now, &timeinfo);
        char tbuf[32];
        strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S UTC", &timeinfo);
        Serial.println(tbuf);
    } else {
        Serial.println("Not Ready (Waiting for SNTP sync)");
    }

    Serial.print("Target MAC:       ");
    if (s_target_mac_set) {
        char mbuf[18];
        snprintf(mbuf, sizeof(mbuf), "%02X:%02X:%02X:%02X:%02X:%02X",
                 s_target_mac[0], s_target_mac[1], s_target_mac[2],
                 s_target_mac[3], s_target_mac[4], s_target_mac[5]);
        Serial.println(mbuf);
    } else {
        Serial.println("(none configured)");
    }

    Serial.print("Gateway Tailnet:  ");
    Serial.println(s_gateway_ip.length() > 0 ? s_gateway_ip : "(none configured)");

    Serial.print("Device Name:      ");
    Serial.println(s_device_name.length() > 0 ? s_device_name : "(none configured)");

    Serial.print("Pairing Secret:   ");
    Serial.println(s_secret_set ? "Configured (32 bytes, confidential)" : "(not set)");

    Serial.print("HTTP Relay Port:  TCP ");
    Serial.println(RELAY_PORT);
    Serial.println("--------------------------------");
    Serial.println();
}

static void handlePair() {
    if (!s_secret_set) {
        Serial.println("Error: Secret key is not set. Run 'gen-key' or 'set-key <key>' first.");
        return;
    }
    if (!isTailnetAddress(s_gateway_ip.c_str())) {
        Serial.println("Error: Gateway Tailnet IP (100.64.0.0/10) is not configured. Run 'set-gateway <tailnet-ip>' first.");
        return;
    }
    if (!isValidDeviceName(s_device_name)) {
        Serial.println("Error: Device name is not configured or invalid. Run 'set-name <name>' first.");
        return;
    }

    // JSON payload: {"v":1,"host":"<gateway>","key":"<key>","name":"<name>"}
    String json = "{\"v\":1,\"host\":\"";
    json += escapeJsonString(s_gateway_ip);
    json += "\",\"key\":\"";
    json += escapeJsonString(s_secret_key);
    json += "\",\"name\":\"";
    json += escapeJsonString(s_device_name);
    json += "\"}";

    String encoded_data = encodeBase64Url((const uint8_t*)json.c_str(), json.length());

    Serial.println();
    Serial.println("=== Client Pairing URI ===");
    Serial.print("seliawake://pair?data=");
    Serial.println(encoded_data);
    Serial.println("==========================");
    Serial.println("Scan QR code or import this URI into Selia Waker app.");
    Serial.println();
}

static int parseArgs(char* line, char* argv[], int max_args) {
    int argc = 0;
    char* p = line;
    while (*p && argc < max_args) {
        while (*p == ' ') p++;
        if (*p == '\0') break;

        if (*p == '"') {
            p++;
            argv[argc++] = p;
            while (*p && *p != '"') p++;
            if (*p == '"') {
                *p = '\0';
                p++;
            } else return -1;
            if (*p && *p != ' ') return -1;
        } else {
            argv[argc++] = p;
            while (*p && *p != ' ') p++;
            if (*p == ' ') {
                *p = '\0';
                p++;
            }
        }
    }
    while (*p == ' ') p++;
    return *p ? -1 : argc;
}

static void processCommand(char* line) {
    char* argv[8];
    int argc = parseArgs(line, argv, 8);
    if (argc < 0) {
        Serial.println("Error: Invalid quoting or too many arguments.");
        return;
    }
    if (argc == 0) return;

    const char* cmd = argv[0];

    if (strcmp(cmd, "help") == 0 || strcmp(cmd, "?") == 0) {
        printHelp();
    } else if (strcmp(cmd, "status") == 0) {
        printStatus();
    } else if (strcmp(cmd, "set-wifi") == 0) {
        if (argc < 2) {
            Serial.println("Usage: set-wifi <ssid> [password]  (Use \"quotes\" for spaces)");
            return;
        }
        String ssid = String(argv[1]);
        String pass = (argc >= 3) ? String(argv[2]) : "";
        if (argc > 3 || ssid.length() == 0 || ssid.length() > 32 || pass.length() > 64) {
            Serial.println("Error: Invalid Wi-Fi arguments or credential lengths.");
            return;
        }

        s_prefs.begin(NVS_NAMESPACE, false);
        size_t s1 = s_prefs.putString("wifi_ssid", ssid);
        size_t s2 = s_prefs.putString("wifi_pass", pass);
        const bool password_saved = s_prefs.getString("wifi_pass", "\x01") == pass;
        s_prefs.end();

        if (s1 != ssid.length() || s2 != pass.length() || !password_saved) {
            Serial.println("Error: Failed to write Wi-Fi credentials to NVS.");
            return;
        }

        s_wifi_ssid = ssid;
        s_wifi_pass = pass;

        Serial.print("Saved Wi-Fi credentials for: ");
        Serial.println(s_wifi_ssid);

        WiFi.disconnect();
        WiFi.begin(s_wifi_ssid.c_str(), s_wifi_pass.c_str());
    } else if (strcmp(cmd, "set-target") == 0) {
        if (argc < 2) {
            Serial.println("Usage: set-target <mac>  (e.g. AA:BB:CC:DD:EE:FF)");
            return;
        }
        uint8_t mac[6];
        if (!parseMac(argv[1], mac)) {
            Serial.println("Error: Invalid MAC format. Must be unicast, non-zero XX:XX:XX:XX:XX:XX.");
            return;
        }
        s_prefs.begin(NVS_NAMESPACE, false);
        size_t written = s_prefs.putBytes("target_mac", mac, 6);
        s_prefs.end();

        if (written != 6) {
            Serial.println("Error: Failed to write target MAC to NVS.");
            return;
        }

        memcpy(s_target_mac, mac, 6);
        s_target_mac_set = true;
        Serial.println("Target MAC saved.");
    } else if (strcmp(cmd, "set-gateway") == 0) {
        if (argc < 2 || !isTailnetAddress(argv[1])) {
            Serial.println("Usage: set-gateway <tailnet-ip>  (Must be in 100.64.0.0/10 range)");
            return;
        }
        String gw = String(argv[1]);
        s_prefs.begin(NVS_NAMESPACE, false);
        size_t written = s_prefs.putString("gateway_ip", gw);
        s_prefs.end();

        if (written == 0) {
            Serial.println("Error: Failed to write gateway IP to NVS.");
            return;
        }

        s_gateway_ip = gw;
        Serial.print("Gateway IP saved: ");
        Serial.println(s_gateway_ip);
    } else if (strcmp(cmd, "set-name") == 0) {
        if (argc < 2) {
            Serial.println("Usage: set-name <name>  (1-80 printable characters, use \"quotes\" for spaces)");
            return;
        }
        String name = String(argv[1]);
        name.trim();
        if (!isValidDeviceName(name)) {
            Serial.println("Error: Device name must be 1 to 80 printable characters.");
            return;
        }
        s_prefs.begin(NVS_NAMESPACE, false);
        size_t written = s_prefs.putString("dev_name", name);
        s_prefs.end();

        if (written == 0) {
            Serial.println("Error: Failed to write device name to NVS.");
            return;
        }

        s_device_name = name;
        Serial.print("Device name saved: ");
        Serial.println(s_device_name);
    } else if (strcmp(cmd, "set-key") == 0) {
        if (argc < 2) {
            Serial.println("Usage: set-key <43-char-unpadded-base64url>");
            return;
        }
        String key_str = String(argv[1]);
        key_str.trim();
        uint8_t key_bytes[32];
        if (!decodeBase64Url32(key_str, key_bytes)) {
            Serial.println("Error: Key must be exactly 43 unpadded base64url characters (32 bytes).");
            return;
        }

        s_prefs.begin(NVS_NAMESPACE, false);
        size_t written = s_prefs.putString("secret_key", key_str);
        s_prefs.end();

        if (written == 0) {
            Serial.println("Error: Failed to write secret key to NVS.");
            return;
        }

        s_secret_key = key_str;
        memcpy(s_secret_bytes, key_bytes, 32);
        s_secret_set = true;

        Serial.println("Pairing key saved successfully. (Key is confidential and never logged)");
    } else if (strcmp(cmd, "gen-key") == 0) {
        uint8_t random_bytes[32];
        esp_fill_random(random_bytes, 32);
        String generated = encodeBase64Url(random_bytes, 32);

        s_prefs.begin(NVS_NAMESPACE, false);
        size_t written = s_prefs.putString("secret_key", generated);
        s_prefs.end();

        if (written == 0) {
            Serial.println("Error: Failed to write generated secret key to NVS.");
            return;
        }

        s_secret_key = generated;
        memcpy(s_secret_bytes, random_bytes, 32);
        s_secret_set = true;

        Serial.println("Generated new 32-byte secret key and stored to NVS.");
        Serial.println("Use 'pair' to export the client pairing URI.");
    } else if (strcmp(cmd, "pair") == 0) {
        handlePair();
    } else if (strcmp(cmd, "test-wake") == 0) {
        if (!s_target_mac_set) {
            Serial.println("Error: Target MAC is not configured. Use 'set-target <mac>'.");
            return;
        }
        if (WiFi.status() != WL_CONNECTED) {
            Serial.println("Error: Wi-Fi is not connected. Connect to Wi-Fi first.");
            return;
        }
        Serial.println("Sending test Magic Packet to 255.255.255.255:9...");
        if (sendMagicPacket()) {
            Serial.println("Success: Magic Packet broadcast sent (102 bytes).");
        } else {
            Serial.println("Error: UDP send call failed.");
        }
    } else if (strcmp(cmd, "reset") == 0) {
        if (!s_prefs.begin(NVS_NAMESPACE, false)) {
            Serial.println("Error: Cannot open NVS.");
            return;
        }
        const bool cleared = s_prefs.clear();
        s_prefs.end();
        if (!cleared) {
            Serial.println("Error: Failed to clear NVS.");
            return;
        }
        WiFi.disconnect();
        s_wifi_ssid = "";
        s_wifi_pass = "";
        s_target_mac_set = false;
        s_gateway_ip = "";
        s_device_name = "";
        s_secret_key = "";
        s_secret_set = false;
        memset(s_secret_bytes, 0, sizeof(s_secret_bytes));
        Serial.println("Factory reset: All settings cleared from NVS.");
    } else if (strcmp(cmd, "reboot") == 0) {
        Serial.println("Rebooting ESP32...");
        Serial.flush();
        delay(100);
        esp_restart();
    } else {
        Serial.print("Unknown command: ");
        Serial.println(cmd);
        Serial.println("Type 'help' for available commands.");
    }
}

// ============================================================================
// Setup & Main Loop
// ============================================================================

void setup() {
    Serial.begin(115200);
    delay(200);

    Serial.println();
    Serial.println("=================================================");
    Serial.println(" Selia Waker ESP32 Companion Relay v1.0");
    Serial.println("=================================================");

    loadSettings();

    // SNTP time synchronization (UTC)
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");

    // Wi-Fi initialization
    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    if (s_wifi_ssid.length() > 0) {
        Serial.print("Connecting to Wi-Fi: ");
        Serial.println(s_wifi_ssid);
        WiFi.begin(s_wifi_ssid.c_str(), s_wifi_pass.c_str());
    } else {
        Serial.println("Wi-Fi not configured. Use 'set-wifi <ssid> [password]' in Serial.");
    }

    // Start minimal bounded HTTP server
    s_server.begin();
    Serial.print("Bounded HTTP Relay listening on port ");
    Serial.println(RELAY_PORT);
    Serial.println("Type 'help' for command reference.");
    Serial.println();
}

void loop() {
    // Process incoming HTTP connections with bounded buffers and timeouts
    WiFiClient client = s_server.available();
    if (client) {
        handleHttpClient(client);
    }

    // Serial CLI Non-blocking Line Reader with Overlong Line Discard
    while (Serial.available() > 0) {
        char c = (char)Serial.read();
        if (c == '\r') continue;
        if (c == '\n') {
            if (s_serial_overflow) {
                s_serial_overflow = false;
                s_serial_pos = 0;
                Serial.println("Error: Command exceeds line buffer limit (discarded).");
            } else {
                s_serial_buf[s_serial_pos] = '\0';
                processCommand(s_serial_buf);
                s_serial_pos = 0;
            }
        } else {
            if (s_serial_overflow) {
                // Keep discarding characters until '\n'
            } else if (s_serial_pos + 1 < SERIAL_BUF_SIZE) {
                s_serial_buf[s_serial_pos++] = c;
            } else {
                // Buffer overflow detected: mark overflow and discard
                s_serial_overflow = true;
                s_serial_pos = 0;
            }
        }
    }

    // Periodic Wi-Fi Health Check & Non-blocking Auto-Reconnect
    unsigned long now_ms = millis();
    if (now_ms - s_last_wifi_check >= 10000) {
        s_last_wifi_check = now_ms;
        if (s_wifi_ssid.length() > 0 && WiFi.status() != WL_CONNECTED) {
            WiFi.disconnect();
            WiFi.begin(s_wifi_ssid.c_str(), s_wifi_pass.c_str());
        }
    }
}
