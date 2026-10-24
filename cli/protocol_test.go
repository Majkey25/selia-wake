package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
)

const vectorKey = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
const vectorNonce = "AAECAwQFBgcICQoLDA0ODw"
const vectorTime int64 = 1800000000

func testPairing() pairing { return pairing{1, "100.101.102.103", vectorKey, "Home"} }

func signedBody(t *testing.T, timestamp int64, nonce string) []byte {
	t.Helper()
	key, err := decodeKey(vectorKey)
	if err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(wakeRequest{timestamp, nonce, signWake(key, timestamp, nonce)})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func testAuth(t *testing.T) *authorizer {
	t.Helper()
	a, err := newAuthorizer(vectorKey)
	if err != nil {
		t.Fatal(err)
	}
	return a
}

func requireCode(t *testing.T, err error, code string) {
	t.Helper()
	var failure *protocolError
	if !errors.As(err, &failure) || failure.code != code {
		t.Fatalf("want %s, got %v", code, err)
	}
}

func TestDartProtocolVector(t *testing.T) {
	key, _ := decodeKey(vectorKey)
	if got := signWake(key, vectorTime, vectorNonce); got != "78b662fee46d77d5abb169a1148b0ddaad174ae3d0e21c1448ab0e9eaf48a009" {
		t.Fatalf("Dart HMAC vector mismatch: %s", got)
	}
	packet, err := magicPacket("02-11:22-33:44-55")
	if err != nil {
		t.Fatal(err)
	}
	want := append(bytes.Repeat([]byte{255}, 6), bytes.Repeat([]byte{2, 17, 34, 51, 68, 85}, 16)...)
	if !bytes.Equal(packet, want) || len(packet) != 102 {
		t.Fatal("incorrect magic packet")
	}
	for _, mac := range []string{"00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "01:00:5e:00:00:01", "hello", "02:11:22:33:44:5500"} {
		if _, err := magicPacket(mac); err == nil {
			t.Fatalf("accepted MAC %q", mac)
		}
	}
}

func TestPairingInteroperability(t *testing.T) {
	p := testPairing()
	// Exact JSON shape and field order emitted by Pairing.encode in protocol.dart.
	data := `{"v":1,"host":"100.101.102.103","key":"` + vectorKey + `","name":"Home"}`
	want := "seliawake://pair?data=" + base64.RawURLEncoding.EncodeToString([]byte(data))
	got, err := p.encode()
	if err != nil || got != want {
		t.Fatalf("pairing vector mismatch: %v", err)
	}
	for _, code := range []string{want, " \n" + want + "\n", "\uFEFF" + want + "\uFEFF", "seliawake://pair?data=" + base64.URLEncoding.EncodeToString([]byte(data))} {
		parsed, err := parsePairing(code)
		if err != nil || parsed != p {
			t.Fatalf("pairing did not roundtrip: %v", err)
		}
	}
	for _, host := range []string{"127.0.0.1", "192.168.1.1", "100.63.0.1", "100.128.0.1", "example.com", "::ffff:100.100.1.1", "100.100.1.1:80"} {
		p.Host = host
		if p.validate() == nil {
			t.Fatalf("accepted host %s", host)
		}
	}
	p = testPairing()
	for _, key := range []string{vectorKey + "=", vectorKey[:42] + "9", strings.Repeat("a", 42)} {
		p.Key = key
		if p.validate() == nil {
			t.Fatal("accepted invalid or noncanonical key")
		}
	}
	for _, code := range []string{want + "&data=x", want + "&host=127.0.0.1", want + "#x", strings.Replace(want, "pair?", "pair/path?", 1), strings.Repeat("a", 2049)} {
		if _, err := parsePairing(code); err == nil {
			t.Fatal("accepted invalid pairing URI")
		}
	}
	p = testPairing()
	p.Name = strings.Repeat("😀", 41)
	if p.validate() == nil {
		t.Fatal("name length must match Dart UTF-16 length")
	}
	p.Name = " \uFEFF\t"
	if p.validate() == nil {
		t.Fatal("name must not contain only Dart whitespace")
	}
}

func TestAuthorizationBoundsAndQuota(t *testing.T) {
	a := testAuth(t)
	valid := signedBody(t, vectorTime, vectorNonce)
	badSignature := bytes.Replace(valid, []byte(`"signature":"78`), []byte(`"signature":"00`), 1)
	for i := 0; i < 100; i++ {
		requireCode(t, a.authorize(badSignature, vectorTime), "unauthorized")
		requireCode(t, a.authorize(signedBody(t, vectorTime-31, vectorNonce), vectorTime), "expired")
	}
	if err := a.authorize(valid, vectorTime); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 100; i++ {
		requireCode(t, a.authorize(valid, vectorTime), "replay")
	}
	for i := 1; i < 60; i++ {
		if err := a.authorize(signedBody(t, vectorTime, fmt.Sprintf("%022d", i)), vectorTime); err != nil {
			t.Fatal(err)
		}
	}
	requireCode(t, a.authorize(signedBody(t, vectorTime, fmt.Sprintf("%022d", 60)), vectorTime), "rate_limited")
	if len(a.nonces) != 60 || a.attempts != 60 {
		t.Fatal("invalid requests affected quota or replay store")
	}
	if err := a.authorize(signedBody(t, vectorTime+60, vectorNonce), vectorTime+60); err != nil || len(a.nonces) != 1 {
		t.Fatalf("TTL or quota did not reset: %v", err)
	}
	for _, delta := range []int64{-30, 30} {
		if err := testAuth(t).authorize(signedBody(t, vectorTime+delta, vectorNonce), vectorTime); err != nil {
			t.Fatalf("boundary timestamp rejected: %v", err)
		}
	}
	// Exercise capacity independently of the lower wake quota.
	a = testAuth(t)
	for i := 0; i < 128; i++ {
		a.nonces[fmt.Sprint(i)] = vectorTime + 60
	}
	requireCode(t, a.authorize(valid, vectorTime), "rate_limited")
	if len(a.nonces) != 128 {
		t.Fatal("replay capacity exceeded")
	}
}

func TestAuthorizationRejectsAmbiguousShapes(t *testing.T) {
	valid := string(signedBody(t, vectorTime, vectorNonce))
	for _, body := range []string{
		`{}`, `null`, `[]`, valid + `{}`, valid[:len(valid)-1] + `,"mac":"02:11:22:33:44:55"}`,
		strings.Replace(valid, `"timestamp":1800000000`, `"timestamp":1800000000.0`, 1),
		strings.Replace(valid, `"timestamp":1800000000`, `"timestamp":null`, 1),
		strings.Replace(valid, `"timestamp":1800000000`, `"timestamp":9223372036854775808`, 1),
		valid[:len(valid)-1] + `,"nonce":"` + vectorNonce + `"}`,
		strings.Replace(valid, vectorNonce, vectorNonce+"=", 1),
	} {
		requireCode(t, testAuth(t).authorize([]byte(body), vectorTime), "invalid_request")
	}
}

func TestReplayAtFinalFreshSecond(t *testing.T) {
	a := testAuth(t)
	body := signedBody(t, vectorTime+30, vectorNonce)
	if err := a.authorize(body, vectorTime); err != nil {
		t.Fatal(err)
	}
	requireCode(t, a.authorize(body, vectorTime+60), "replay")
	requireCode(t, a.authorize(body, vectorTime+61), "expired")
	if err := a.authorize(signedBody(t, vectorTime+61, vectorNonce), vectorTime+61); err != nil {
		t.Fatal(err)
	}
}

func TestConcurrentAuthorizationSharesQuota(t *testing.T) {
	a := testAuth(t)
	results := make(chan error, 70)
	var wg sync.WaitGroup
	for i := 0; i < 70; i++ {
		body := signedBody(t, vectorTime, fmt.Sprintf("%022d", i))
		wg.Add(1)
		go func() {
			defer wg.Done()
			results <- a.authorize(body, vectorTime)
		}()
	}
	wg.Wait()
	close(results)
	accepted := 0
	for err := range results {
		if err == nil {
			accepted++
		} else {
			requireCode(t, err, "rate_limited")
		}
	}
	if accepted != 60 || len(a.nonces) != 60 {
		t.Fatalf("concurrent quota admitted %d requests", accepted)
	}
}
