package main

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"unsafe"
)

func TestWindowsRefusesInheritedOrBroadenedACL(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "private")
	c := config{Role: "user", Pairing: testPairing()}
	if err := saveConfig(dir, c); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "config.json")
	sid, err := currentSID()
	if err != nil {
		t.Fatal(err)
	}
	sddl, _ := syscall.UTF16PtrFromString("O:" + sid + "D:P(A;;FA;;;" + sid + ")(A;;FR;;;WD)")
	var descriptor uintptr
	ok, _, err := convertSD.Call(uintptr(unsafe.Pointer(sddl)), 1, uintptr(unsafe.Pointer(&descriptor)), 0)
	if ok == 0 {
		t.Fatal(err)
	}
	defer syscall.LocalFree(syscall.Handle(descriptor))
	p, _ := syscall.UTF16PtrFromString(path)
	ok, _, err = advapi.NewProc("SetFileSecurityW").Call(uintptr(unsafe.Pointer(p)), 4|0x80000000, descriptor)
	if ok == 0 {
		t.Fatal(err)
	}
	if _, err := loadConfig(dir); err == nil {
		t.Fatal("read a secret after granting Everyone read access")
	}
	public := filepath.Join(t.TempDir(), "inherited")
	if err := os.Mkdir(public, 0700); err != nil {
		t.Fatal(err)
	}
	if saveConfig(public, c) == nil {
		t.Fatal("saved secrets inside an inherited directory ACL")
	}
}
