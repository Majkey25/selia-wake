//go:build linux || darwin

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestUnixRefusesPublicPermissionsAndLinks(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "private")
	c := config{Role: "user", Pairing: testPairing()}
	if err := saveConfig(dir, c); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "config.json")
	if err := os.Chmod(path, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := loadConfig(dir); err == nil {
		t.Fatal("read publicly accessible config")
	}
	if err := os.Chmod(path, 0600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link")
	if err := os.Symlink(path, link); err != nil {
		t.Fatal(err)
	}
	if _, err := openPrivate(link); err == nil {
		t.Fatal("read configuration through symlink")
	}
	if err := os.Chmod(dir, 0755); err != nil {
		t.Fatal(err)
	}
	if _, err := loadConfig(dir); err == nil {
		t.Fatal("read config in a public directory")
	}
}
