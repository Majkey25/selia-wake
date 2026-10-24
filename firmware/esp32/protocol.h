#pragma once

#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstring>

static const size_t MAX_BODY_SIZE = 1024;
static const int NONCE_EXPIRY_SEC = 60;
static const int FRESHNESS_SEC = 30;

struct WakeRequest {
    int64_t timestamp;
    char nonce[23];
    char signature[65];
};

static inline bool isBase64UrlChar(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') || c == '-' || c == '_';
}

static int64_t nonceExpiry(int64_t now, int64_t timestamp) {
    const int64_t minimum = now + NONCE_EXPIRY_SEC;
    const int64_t final_second = timestamp + FRESHNESS_SEC + 1;
    return minimum > final_second ? minimum : final_second;
}

static bool parseWakeJson(const char* body, size_t body_len, WakeRequest& req) {
    if (body_len == 0 || body_len > MAX_BODY_SIZE) return false;
    const char* p = body;
    const char* end = body + body_len;
    auto skipWs = [&]() {
        while (p < end && (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')) p++;
    };
    skipWs();
    if (p >= end || *p++ != '{') return false;
    bool has_ts = false, has_nonce = false, has_sig = false, closed = false;
    int field_count = 0;
    while (p < end) {
        skipWs();
        if (p < end && *p == '}') {
            p++;
            closed = true;
            break;
        }
        if (field_count > 0) {
            if (p >= end || *p++ != ',') return false;
            skipWs();
        }
        if (p >= end || *p++ != '"') return false;
        const char* key_start = p;
        while (p < end && *p != '"') {
            if (*p == '\\') return false;
            p++;
        }
        if (p >= end) return false;
        const size_t key_len = p - key_start;
        p++;
        skipWs();
        if (p >= end || *p++ != ':') return false;
        skipWs();
        if (key_len == 9 && strncmp(key_start, "timestamp", 9) == 0) {
            if (has_ts || p >= end || !isdigit((unsigned char)*p)) return false;
            if (*p == '0' && p + 1 < end && isdigit((unsigned char)*(p + 1))) return false;
            uint64_t val = 0;
            while (p < end && isdigit((unsigned char)*p)) {
                const unsigned digit = *p++ - '0';
                if (val > (4102444800ULL - digit) / 10) return false;
                val = val * 10 + digit;
            }
            if (val < 1000000000ULL) return false;
            req.timestamp = (int64_t)val;
            has_ts = true;
        } else if ((key_len == 5 && strncmp(key_start, "nonce", 5) == 0) ||
                   (key_len == 9 && strncmp(key_start, "signature", 9) == 0)) {
            const bool nonce = key_len == 5;
            if ((nonce ? has_nonce : has_sig) || p >= end || *p++ != '"') return false;
            const char* start = p;
            while (p < end && *p != '"') {
                const char c = *p++;
                if (nonce ? !isBase64UrlChar(c) : !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return false;
            }
            const size_t length = nonce ? 22 : 64;
            if (p >= end || size_t(p - start) != length) return false;
            char* output = nonce ? req.nonce : req.signature;
            memcpy(output, start, length);
            output[length] = '\0';
            p++;
            if (nonce) has_nonce = true; else has_sig = true;
        } else {
            return false;
        }
        field_count++;
    }
    skipWs();
    return p == end && closed && field_count == 3 && has_ts && has_nonce && has_sig;
}
