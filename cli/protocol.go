package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/netip"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"
)

const relayPort = 45879
const requestLimit = 1024
const freshnessSeconds = 30
const replaySeconds = 60
const maxReplayEntries = 128
const quotaSeconds = 60
const wakeQuota = 60

var nonceShape = regexp.MustCompile(`^[A-Za-z0-9_-]{22}$`)
var signatureShape = regexp.MustCompile(`^[0-9a-f]{64}$`)
var macShape = regexp.MustCompile(`^(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$`)
var tailnet = netip.MustParsePrefix("100.64.0.0/10")

type pairing struct {
	Version int    `json:"v"`
	Host    string `json:"host"`
	Key     string `json:"key"`
	Name    string `json:"name"`
}

// Dart's String.trim also removes the byte-order mark.
func trimDart(s string) string {
	return strings.TrimFunc(s, func(r rune) bool { return unicode.IsSpace(r) || r == '\uFEFF' })
}

func (p pairing) validate() error {
	ip, err := netip.ParseAddr(p.Host)
	if err != nil || !ip.Is4() || !tailnet.Contains(ip) || p.Version != 1 ||
		!utf8.ValidString(p.Name) || trimDart(p.Name) == "" || len(utf16.Encode([]rune(p.Name))) > 80 {
		return errors.New("invalid_pairing")
	}
	_, err = decodeKey(p.Key)
	return err
}

func decodeKey(key string) ([]byte, error) {
	b, err := base64.RawURLEncoding.Strict().DecodeString(key)
	if err != nil || len(b) != 32 || base64.RawURLEncoding.EncodeToString(b) != key {
		return nil, errors.New("invalid_key")
	}
	return b, nil
}

func randomKey(size int) (string, error) {
	b := make([]byte, size)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

func (p pairing) encode() (string, error) {
	if err := p.validate(); err != nil {
		return "", err
	}
	b, err := json.Marshal(p)
	if err != nil {
		return "", err
	}
	return "seliawake://pair?data=" + base64.RawURLEncoding.EncodeToString(b), nil
}

func parsePairing(code string) (pairing, error) {
	var p pairing
	invalid := errors.New("invalid_pairing")
	if len(code) > 2048 {
		return p, invalid
	}
	u, err := url.Parse(trimDart(code))
	if err != nil || u.Scheme != "seliawake" || u.Host != "pair" || u.User != nil || u.Path != "" || u.Fragment != "" {
		return p, invalid
	}
	q, err := url.ParseQuery(u.RawQuery)
	if err != nil || len(q) != 1 || len(q["data"]) != 1 {
		return p, invalid
	}
	// Dart accepts both padded and unpadded base64url pairing data.
	b, err := base64.URLEncoding.DecodeString(q.Get("data") + strings.Repeat("=", (4-len(q.Get("data"))%4)%4))
	if err != nil {
		return p, invalid
	}
	fields, err := jsonObject(b)
	if err != nil || fields["v"] == nil || fields["host"] == nil || fields["key"] == nil || fields["name"] == nil ||
		json.Unmarshal(fields["v"], &p.Version) != nil || json.Unmarshal(fields["host"], &p.Host) != nil ||
		json.Unmarshal(fields["key"], &p.Key) != nil || json.Unmarshal(fields["name"], &p.Name) != nil || p.validate() != nil {
		return pairing{}, invalid
	}
	return p, nil
}

// Reject duplicate fields instead of silently choosing one interpretation.
func jsonObject(data []byte) (map[string]json.RawMessage, error) {
	invalid := errors.New("invalid_request")
	if !utf8.Valid(data) {
		return nil, invalid
	}
	d := json.NewDecoder(bytes.NewReader(data))
	t, err := d.Token()
	if err != nil || t != json.Delim('{') {
		return nil, invalid
	}
	fields := make(map[string]json.RawMessage)
	for d.More() {
		t, err = d.Token()
		key, ok := t.(string)
		if err != nil || !ok || fields[key] != nil {
			return nil, invalid
		}
		var value json.RawMessage
		if err := d.Decode(&value); err != nil {
			return nil, invalid
		}
		fields[key] = value
	}
	if _, err := d.Token(); err != nil {
		return nil, invalid
	}
	if _, err := d.Token(); err != io.EOF {
		return nil, invalid
	}
	return fields, nil
}

func magicPacket(mac string) ([]byte, error) {
	if !macShape.MatchString(mac) {
		return nil, errors.New("invalid_mac")
	}
	b, err := hex.DecodeString(strings.NewReplacer(":", "", "-", "").Replace(mac))
	if err != nil || b[0]&1 != 0 || bytes.Equal(b, make([]byte, 6)) {
		return nil, errors.New("invalid_mac")
	}
	return append(bytes.Repeat([]byte{255}, 6), bytes.Repeat(b, 16)...), nil
}

type wakeRequest struct {
	Timestamp int64  `json:"timestamp"`
	Nonce     string `json:"nonce"`
	Signature string `json:"signature"`
}

func signWake(key []byte, timestamp int64, nonce string) string {
	h := hmac.New(sha256.New, key)
	_, _ = fmt.Fprintf(h, "%d\n%s\nwake-v1", timestamp, nonce)
	return hex.EncodeToString(h.Sum(nil))
}

type protocolError struct {
	code   string
	status int
}

func (e *protocolError) Error() string { return e.code }

type authorizer struct {
	mu       sync.Mutex
	key      []byte
	nonces   map[string]int64
	window   int64
	attempts int
}

func newAuthorizer(key string) (*authorizer, error) {
	b, err := decodeKey(key)
	if err != nil {
		return nil, err
	}
	return &authorizer{key: b, nonces: make(map[string]int64)}, nil
}

func (a *authorizer) authorize(body []byte, now int64) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	for nonce, expiry := range a.nonces {
		if expiry <= now {
			delete(a.nonces, nonce)
		}
	}
	fields, err := jsonObject(body)
	var r wakeRequest
	if err != nil || len(fields) != 3 || fields["timestamp"] == nil || fields["nonce"] == nil || fields["signature"] == nil ||
		bytes.Equal(fields["timestamp"], []byte("null")) || json.Unmarshal(body, &r) != nil ||
		!nonceShape.MatchString(r.Nonce) || !signatureShape.MatchString(r.Signature) {
		return &protocolError{"invalid_request", 400}
	}
	if r.Timestamp < now-freshnessSeconds || r.Timestamp > now+freshnessSeconds {
		return &protocolError{"expired", 401}
	}
	if !hmac.Equal([]byte(signWake(a.key, r.Timestamp, r.Nonce)), []byte(r.Signature)) {
		return &protocolError{"unauthorized", 401}
	}
	if _, ok := a.nonces[r.Nonce]; ok {
		return &protocolError{"replay", 409}
	}
	if len(a.nonces) >= maxReplayEntries {
		return &protocolError{"rate_limited", 429}
	}
	if now-a.window >= quotaSeconds || now < a.window {
		a.window, a.attempts = now, 0
	}
	if a.attempts >= wakeQuota {
		return &protocolError{"rate_limited", 429}
	}
	a.attempts++
	a.nonces[r.Nonce] = max(now+replaySeconds, r.Timestamp+freshnessSeconds+1)
	return nil
}
