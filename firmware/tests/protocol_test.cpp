#include "../esp32/protocol.h"
#include <cassert>
#include <string>

int main() {
    const std::string suffix = ",\"nonce\":\"AAECAwQFBgcICQoLDA0ODw\",\"signature\":\"78b662fee46d77d5abb169a1148b0ddaad174ae3d0e21c1448ab0e9eaf48a009\"}";
    const std::string valid = "{\"timestamp\":1800000000" + suffix;
    WakeRequest request{};
    assert(parseWakeJson(valid.data(), valid.size(), request));
    assert(request.timestamp == 1800000000);
    assert(std::string(request.nonce) == "AAECAwQFBgcICQoLDA0ODw");
    assert(std::string(request.signature) == "78b662fee46d77d5abb169a1148b0ddaad174ae3d0e21c1448ab0e9eaf48a009");
    for (const char* timestamp : {"-0", "-1800000000", "01800000000", "1800000000.0", "1800000000e0", "null", "4102444801", "18446744075509551616"}) {
        const auto body = std::string("{\"timestamp\":") + timestamp + suffix;
        assert(!parseWakeJson(body.data(), body.size(), request));
    }
    for (const auto& body : {valid.substr(0, valid.size() - 1), valid + "x", valid + std::string("\0x", 2), valid.substr(0, valid.size() - 1) + ",\"timestamp\":1800000000}", valid.substr(0, valid.size() - 1) + ",\"mac\":\"02:11:22:33:44:55\"}", std::string(1025, ' ')}) {
        assert(!parseWakeJson(body.data(), body.size(), request));
    }
    const int64_t now = 1800000000;
    assert(nonceExpiry(now, now + 30) > now + 60);
    assert(nonceExpiry(now, now + 30) == now + 61);
    assert(nonceExpiry(now, now) == now + 60);
    assert(nonceExpiry(now, now - 30) == now + 60);
}
