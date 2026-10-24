package main

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestConfigIsPrivateAtomicAndNeverOverwritten(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "config")
	c := config{Role: "user", Pairing: testPairing()}
	if err := saveConfig(dir, c); err != nil {
		t.Fatal(err)
	}
	got, err := loadConfig(dir)
	if err != nil || got != c {
		t.Fatalf("config roundtrip: %v", err)
	}
	other := c
	other.Pairing.Name = "Replacement"
	if saveConfig(dir, other) == nil {
		t.Fatal("overwrote an existing config")
	}
	got, err = loadConfig(dir)
	if err != nil || got != c {
		t.Fatal("failed write changed the config")
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 || entries[0].Name() != "config.json" {
		t.Fatal("temporary secret file left behind")
	}
	// Two creators may race, but only one complete configuration can win.
	raced := filepath.Join(t.TempDir(), "raced")
	if err := makePrivateDir(raced); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errors := make(chan error, 2)
	for _, value := range []config{c, other} {
		wg.Add(1)
		go func() { defer wg.Done(); errors <- saveConfig(raced, value) }()
	}
	wg.Wait()
	close(errors)
	successes := 0
	for err := range errors {
		if err == nil {
			successes++
		}
	}
	if successes != 1 {
		t.Fatalf("atomic creation winners: %d", successes)
	}
	if _, err := loadConfig(raced); err != nil {
		t.Fatal(err)
	}
}

func TestCLIImportStatusAndExplicitExport(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "config")
	code, _ := testPairing().encode()
	var out bytes.Buffer
	call := func(input string, args ...string) error {
		out.Reset()
		return run(context.Background(), append([]string{"--config-dir", dir}, args...), strings.NewReader(input), &out)
	}
	if err := call(code+"\n", "pair", "--stdin"); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out.String(), vectorKey) || strings.Contains(out.String(), code) {
		t.Fatal("import printed pairing secret")
	}
	if err := call("", "status"); err != nil || strings.Contains(out.String(), vectorKey) || !strings.Contains(out.String(), "unknown") {
		t.Fatalf("status leaked a secret or claimed remote state: %v", err)
	}
	if err := call("", "export-pairing"); err == nil || out.Len() != 0 {
		t.Fatal("export did not require explicit disclosure")
	}
	if err := call("", "export-pairing", "--show-secret"); err != nil || strings.TrimSpace(out.String()) != code {
		t.Fatalf("explicit export failed: %v", err)
	}
	if call(code, "pair", "--stdin") == nil {
		t.Fatal("import overwrote the pairing")
	}
	for _, args := range [][]string{{"pair", code}, {"pair", "--secret=" + vectorKey}, {"wake", vectorKey}, {"serve"}, {"send-local"}} {
		err := call("", args...)
		if err == nil || strings.Contains(err.Error(), vectorKey) || strings.Contains(err.Error(), code) || out.Len() != 0 {
			t.Fatal("invalid command accepted or secret reflected")
		}
	}
	if err := run(context.Background(), []string{"help"}, strings.NewReader(""), io.Discard); err != nil {
		t.Fatal(err)
	}
}

func TestInvalidConfigDoesNotCreateSecret(t *testing.T) {
	for _, c := range []config{
		{Role: "other", Pairing: testPairing()},
		{Role: "user", Pairing: testPairing(), MAC: "02:11:22:33:44:55"},
		{Role: "waker", Pairing: testPairing(), LAN: "127.0.0.1", Broadcast: "255.255.255.255", MAC: "02:11:22:33:44:55"},
	} {
		dir := filepath.Join(t.TempDir(), "config")
		if saveConfig(dir, c) == nil {
			t.Fatal("invalid configuration saved")
		}
		if _, err := os.Stat(dir); !os.IsNotExist(err) {
			t.Fatal("invalid config created files")
		}
	}
}
