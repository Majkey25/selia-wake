package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime"
	"net"
	"net/http"
	"sync"
	"time"
)

func sendLocal(c config) error {
	if err := c.checkLAN(); err != nil {
		return err
	}
	packet, err := magicPacket(c.MAC)
	if err != nil {
		return err
	}
	return sendPacket(packet, &net.UDPAddr{IP: net.ParseIP(c.LAN)}, &net.UDPAddr{IP: net.ParseIP(c.Broadcast), Port: 9})
}

// Address injection is private to packet transport tests; commands validate LAN first.
func sendPacket(packet []byte, source, destination *net.UDPAddr) error {
	conn, err := net.DialUDP("udp4", source, destination)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err := conn.SetWriteDeadline(time.Now().Add(2 * time.Second)); err != nil {
		return err
	}
	n, err := conn.Write(packet)
	if err == nil && n != len(packet) {
		err = io.ErrShortWrite
	}
	return err
}

func relayHandler(auth *authorizer, send func() error) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Connection", "close")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		fail := func(code string, status int) {
			w.WriteHeader(status)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": code})
		}
		mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
		if r.Method != http.MethodPost || r.RequestURI != "/v1/wake" || err != nil || mediaType != "application/json" ||
			len(r.Header.Values("Content-Type")) != 1 || r.Header.Get("Content-Encoding") != "" ||
			r.ContentLength < 0 || r.ContentLength > requestLimit || len(r.TransferEncoding) != 0 {
			fail("invalid_request", 400)
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, requestLimit)
		defer r.Body.Close()
		body, err := io.ReadAll(r.Body)
		if err != nil {
			fail("invalid_request", 400)
			return
		}
		if err := auth.authorize(body, time.Now().Unix()); err != nil {
			var failure *protocolError
			if errors.As(err, &failure) {
				fail(failure.code, failure.status)
			} else {
				fail("invalid_request", 400)
			}
			return
		}
		if err := send(); err != nil {
			fail("send_failed", 503)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "sent"})
	})
}

const maxConnections = 8

type limitedListener struct {
	net.Listener
	slots chan struct{}
}

type limitedConn struct {
	net.Conn
	once    sync.Once
	release func()
}

func (c *limitedConn) Close() error {
	err := c.Conn.Close()
	c.once.Do(c.release)
	return err
}

func (l *limitedListener) Accept() (net.Conn, error) {
	for {
		conn, err := l.Listener.Accept()
		if err != nil {
			return nil, err
		}
		select {
		case l.slots <- struct{}{}:
			if err := conn.SetDeadline(time.Now().Add(8 * time.Second)); err != nil {
				conn.Close()
				<-l.slots
				continue
			}
			return &limitedConn{Conn: conn, release: func() { <-l.slots }}, nil
		default:
			conn.Close()
		}
	}
}

func newRelayServer(handler http.Handler) *http.Server {
	s := &http.Server{
		Handler: handler, ReadHeaderTimeout: 2 * time.Second,
		ReadTimeout: 4 * time.Second, WriteTimeout: 4 * time.Second,
		IdleTimeout: 2 * time.Second, MaxHeaderBytes: 2048,
		ErrorLog: log.New(io.Discard, "", 0),
	}
	s.SetKeepAlivesEnabled(false)
	return s
}

func serve(ctx context.Context, c config, out io.Writer) error {
	if err := c.checkLAN(); err != nil {
		return err
	}
	if _, err := assignedInterface(c.Pairing.Host); err != nil {
		return fmt.Errorf("Tailscale address: %w", err)
	}
	auth, err := newAuthorizer(c.Pairing.Key)
	if err != nil {
		return err
	}
	// No wildcard listener, hostname lookup, proxy or runtime URL is accepted.
	listener, err := net.Listen("tcp4", net.JoinHostPort(c.Pairing.Host, fmt.Sprint(relayPort)))
	if err != nil {
		return fmt.Errorf("cannot bind Tailscale listener; stop any GUI/CLI relay using this port: %w", err)
	}
	defer listener.Close()
	s := newRelayServer(relayHandler(auth, func() error { return sendLocal(c) }))
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			_ = s.Close()
		case <-done:
		}
	}()
	defer close(done)
	fmt.Fprintf(out, "Listening on %s:%d. Ctrl+C stops the Waker.\n", c.Pairing.Host, relayPort)
	err = s.Serve(&limitedListener{Listener: listener, slots: make(chan struct{}, maxConnections)})
	if errors.Is(err, http.ErrServerClosed) && ctx.Err() != nil {
		return nil
	}
	return err
}

func newWakeClient() *http.Client {
	transport := &http.Transport{
		Proxy: nil, DialContext: (&net.Dialer{Timeout: 4 * time.Second}).DialContext,
		DisableKeepAlives: true, DisableCompression: true,
		MaxConnsPerHost: 1, MaxResponseHeaderBytes: 2048,
		ResponseHeaderTimeout: 4 * time.Second,
	}
	return &http.Client{
		Transport: transport, Timeout: 8 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse },
	}
}

func requestWake(ctx context.Context, p pairing, client *http.Client) error {
	if err := p.validate(); err != nil {
		return err
	}
	key, err := decodeKey(p.Key)
	if err != nil {
		return err
	}
	nonce, err := randomKey(16)
	if err != nil {
		return err
	}
	timestamp := time.Now().Unix()
	body, err := json.Marshal(wakeRequest{timestamp, nonce, signWake(key, timestamp, nonce)})
	if err != nil {
		return err
	}
	r, err := http.NewRequestWithContext(ctx, http.MethodPost, "http://"+net.JoinHostPort(p.Host, fmt.Sprint(relayPort))+"/v1/wake", bytes.NewReader(body))
	if err != nil {
		return err
	}
	r.Header.Set("Content-Type", "application/json")
	response, err := client.Do(r)
	if err != nil {
		return errors.New("wake connection failed or timed out")
	}
	defer response.Body.Close()
	b, err := io.ReadAll(io.LimitReader(response.Body, requestLimit+1))
	if err != nil || len(b) > requestLimit {
		return errors.New("invalid_response")
	}
	fields, err := jsonObject(b)
	if err != nil {
		return errors.New("invalid_response")
	}
	var status string
	if response.StatusCode == 200 && len(fields) == 1 && json.Unmarshal(fields["status"], &status) == nil && status == "sent" {
		return nil
	}
	// Never echo untrusted response text into the terminal.
	return fmt.Errorf("wake failed (HTTP %d)", response.StatusCode)
}
