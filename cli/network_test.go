package main

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func startTestServer(t *testing.T, handler http.Handler) (string, *limitedListener) {
	t.Helper()
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	limited := &limitedListener{Listener: l, slots: make(chan struct{}, maxConnections)}
	server := newRelayServer(handler)
	done := make(chan error, 1)
	go func() { done <- server.Serve(limited) }()
	t.Cleanup(func() {
		server.Close()
		if err := <-done; !errors.Is(err, http.ErrServerClosed) {
			t.Errorf("server: %v", err)
		}
	})
	return l.Addr().String(), limited
}

func testClient(t *testing.T, address string) *http.Client {
	t.Helper()
	client := newWakeClient()
	transport := client.Transport.(*http.Transport)
	transport.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
		if addr != "100.101.102.103:45879" {
			return nil, fmt.Errorf("unexpected production destination %s", addr)
		}
		return (&net.Dialer{Timeout: time.Second}).DialContext(ctx, "tcp4", address)
	}
	t.Cleanup(client.CloseIdleConnections)
	return client
}

func TestActualHTTPToUDPPacketAndClient(t *testing.T) {
	udp, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer udp.Close()
	packet, _ := magicPacket("02:11:22:33:44:55")
	auth := testAuth(t)
	address, _ := startTestServer(t, relayHandler(auth, func() error {
		return sendPacket(packet, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)}, udp.LocalAddr().(*net.UDPAddr))
	}))
	client := testClient(t, address)
	if err := requestWake(context.Background(), testPairing(), client); err != nil {
		t.Fatal(err)
	}
	if err := udp.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	buffer := make([]byte, 103)
	n, source, err := udp.ReadFromUDP(buffer)
	if err != nil || !bytes.Equal(buffer[:n], packet) || source.IP.String() != "127.0.0.1" {
		t.Fatalf("UDP packet/source mismatch: %v %v", source, err)
	}
}

func TestHTTPRejectionsAndSendFailure(t *testing.T) {
	var sends atomic.Int32
	auth := testAuth(t)
	address, _ := startTestServer(t, relayHandler(auth, func() error {
		sends.Add(1)
		return errors.New("simulated UDP failure")
	}))
	client := &http.Client{Timeout: 2 * time.Second}
	defer client.CloseIdleConnections()
	now := time.Now().Unix()
	valid := signedBody(t, now, vectorNonce)
	for _, tc := range []struct {
		method, path, contentType string
		body                      []byte
		status                    int
	}{
		{"GET", "/v1/wake", "application/json", valid, 400},
		{"POST", "/health", "application/json", valid, 400},
		{"POST", "/v1/wake?mac=x", "application/json", valid, 400},
		{"POST", "/v1/wake", "text/plain", valid, 400},
		{"POST", "/v1/wake", "application/json", bytes.Repeat([]byte("x"), 1025), 400},
		{"POST", "/v1/wake", "application/json", []byte(`{"mac":"02:11:22:33:44:55"}`), 400},
		{"POST", "/v1/wake", "application/json", signedBody(t, now-31, vectorNonce), 401},
		{"POST", "/v1/wake", "application/json", bytes.Replace(valid, []byte(`"signature":"`), []byte(`"signature":"00`), 1), 400},
		{"POST", "/v1/wake", "application/json", valid, 503},
		{"POST", "/v1/wake", "application/json", valid, 409},
	} {
		r, err := http.NewRequest(tc.method, "http://"+address+tc.path, bytes.NewReader(tc.body))
		if err != nil {
			t.Fatal(err)
		}
		r.Header.Set("Content-Type", tc.contentType)
		response, err := client.Do(r)
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(response.Body)
		response.Body.Close()
		if err != nil || response.StatusCode != tc.status || !strings.Contains(string(body), `"error":`) || strings.Contains(string(body), `"sent"`) {
			t.Fatalf("%s %s: status %d body %s err %v", tc.method, tc.path, response.StatusCode, body, err)
		}
	}
	if sends.Load() != 1 {
		t.Fatalf("unauthorized request caused a send: %d", sends.Load())
	}
	// Production path must reject loopback even though packet tests use it privately.
	c := config{Role: "waker", Pairing: testPairing(), LAN: "127.0.0.1", Broadcast: "127.0.0.1", MAC: "02:11:22:33:44:55"}
	if sendLocal(c) == nil || serve(context.Background(), c, io.Discard) == nil {
		t.Fatal("production LAN validation was bypassed")
	}
}

func TestHTTPTransportBounds(t *testing.T) {
	address, limited := startTestServer(t, relayHandler(testAuth(t), func() error { t.Error("unexpected send"); return nil }))
	for _, raw := range []string{
		"POST /v1/wake HTTP/1.1\r\nHost: test\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n",
		"POST /v1/wake HTTP/1.1\r\nHost: test\r\nContent-Type: application/json\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
		"POST /v1/wake HTTP/1.1\r\nHost: test\r\nX-Large: " + strings.Repeat("a", 8000) + "\r\n\r\n",
	} {
		conn, err := net.DialTimeout("tcp4", address, time.Second)
		if err != nil {
			t.Fatal(err)
		}
		conn.SetDeadline(time.Now().Add(3 * time.Second))
		_, _ = io.WriteString(conn, raw)
		response, err := http.ReadResponse(bufio.NewReader(conn), nil)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		conn.Close()
		if response.StatusCode != 400 && response.StatusCode != 431 {
			t.Fatalf("invalid transport accepted: %d", response.StatusCode)
		}
	}
	var connections []net.Conn
	defer func() {
		for _, conn := range connections {
			conn.Close()
		}
	}()
	for i := 0; i < maxConnections; i++ {
		conn, err := net.DialTimeout("tcp4", address, time.Second)
		if err != nil {
			t.Fatal(err)
		}
		connections = append(connections, conn)
	}
	deadline := time.Now().Add(time.Second)
	for len(limited.slots) != maxConnections && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if len(limited.slots) != maxConnections {
		t.Fatal("connection cap not reached")
	}
	extra, err := net.DialTimeout("tcp4", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer extra.Close()
	extra.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := extra.Read(make([]byte, 1)); err == nil {
		t.Fatal("excess connection was not closed")
	} else if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
		t.Fatal("excess connection was left open")
	}
}

func TestSlowHTTPHeadersTimeOut(t *testing.T) {
	address, _ := startTestServer(t, relayHandler(testAuth(t), func() error { t.Error("unexpected send"); return nil }))
	conn, err := net.DialTimeout("tcp4", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	_, _ = io.WriteString(conn, "POST /v1/wake HTTP/1.1\r\nHost:")
	if _, err := conn.Read(make([]byte, 1)); err == nil {
		t.Fatal("incomplete header received unexpected response")
	} else if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
		t.Fatal("server failed to enforce header deadline")
	}
}

func TestSlowHTTPBodyTimesOut(t *testing.T) {
	address, _ := startTestServer(t, relayHandler(testAuth(t), func() error { t.Error("unexpected send"); return nil }))
	conn, err := net.DialTimeout("tcp4", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	_, _ = io.WriteString(conn, "POST /v1/wake HTTP/1.1\r\nHost: test\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{")
	_, err = io.ReadAll(conn)
	if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
		t.Fatal("server failed to enforce body deadline")
	}
}

func TestClientRejectsRedirectAndOversizedResponse(t *testing.T) {
	for _, mode := range []string{"redirect", "body", "header", "wrong-status"} {
		t.Run(mode, func(t *testing.T) {
			var calls atomic.Int32
			address, _ := startTestServer(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls.Add(1)
				switch mode {
				case "redirect":
					w.Header().Set("Location", "http://127.0.0.1:1/secret")
					w.WriteHeader(302)
				case "body":
					fmt.Fprint(w, strings.Repeat("a", requestLimit+1))
				case "header":
					w.Header().Set("X-Large", strings.Repeat("a", 3000))
					fmt.Fprint(w, `{"status":"sent"}`)
				default:
					fmt.Fprint(w, `{"status":"booted"}`)
				}
			}))
			if requestWake(context.Background(), testPairing(), testClient(t, address)) == nil || calls.Load() != 1 {
				t.Fatal("client accepted invalid response or followed redirect")
			}
		})
	}
}
