package main

import (
	"errors"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"syscall"
	"unsafe"
)

var advapi = syscall.NewLazyDLL("advapi32.dll")
var convertSD = advapi.NewProc("ConvertStringSecurityDescriptorToSecurityDescriptorW")
var getSecurityInfo = advapi.NewProc("GetSecurityInfo")
var getAce = advapi.NewProc("GetAce")
var getSDControl = advapi.NewProc("GetSecurityDescriptorControl")

func currentSID() (string, error) {
	u, err := user.Current()
	if err != nil {
		return "", err
	}
	return u.Uid, nil
}

func privateAttributes() (*syscall.SecurityAttributes, func(), error) {
	sid, err := currentSID()
	if err != nil {
		return nil, nil, err
	}
	sddl, err := syscall.UTF16PtrFromString("O:" + sid + "D:P(A;;FA;;;" + sid + ")")
	if err != nil {
		return nil, nil, err
	}
	var descriptor uintptr
	ok, _, callErr := convertSD.Call(uintptr(unsafe.Pointer(sddl)), 1, uintptr(unsafe.Pointer(&descriptor)), 0)
	if ok == 0 {
		return nil, nil, callErr
	}
	attributes := &syscall.SecurityAttributes{Length: uint32(unsafe.Sizeof(syscall.SecurityAttributes{})), SecurityDescriptor: descriptor}
	return attributes, func() { syscall.LocalFree(syscall.Handle(descriptor)) }, nil
}

type windowsACL struct {
	Revision byte
	Reserved byte
	Size     uint16
	Count    uint16
	Unused   uint16
}

type windowsACE struct {
	Type  byte
	Flags byte
	Size  uint16
	Mask  uint32
	SID   uint32
}

func checkPrivateHandle(f *os.File) error {
	invalid := errors.New("Windows configuration requires a protected owner-only ACL; refusing secret access")
	var info syscall.ByHandleFileInformation
	if err := syscall.GetFileInformationByHandle(syscall.Handle(f.Fd()), &info); err != nil {
		return err
	}
	if info.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 || info.NumberOfLinks != 1 {
		return invalid
	}
	var owner *syscall.SID
	var acl *windowsACL
	var descriptor uintptr
	code, _, _ := getSecurityInfo.Call(f.Fd(), 1, 1|4, uintptr(unsafe.Pointer(&owner)), 0, uintptr(unsafe.Pointer(&acl)), 0, uintptr(unsafe.Pointer(&descriptor)))
	if code != 0 {
		return syscall.Errno(code)
	}
	defer syscall.LocalFree(syscall.Handle(descriptor))
	sid, err := currentSID()
	if err != nil {
		return err
	}
	if owner == nil || acl == nil || acl.Count != 1 {
		return invalid
	}
	ownerSID, err := owner.String()
	if err != nil || ownerSID != sid {
		return invalid
	}
	var control uint16
	var revision uint32
	ok, _, _ := getSDControl.Call(descriptor, uintptr(unsafe.Pointer(&control)), uintptr(unsafe.Pointer(&revision)))
	if ok == 0 || control&0x1000 == 0 { // SE_DACL_PROTECTED
		return invalid
	}
	var ace *windowsACE
	ok, _, _ = getAce.Call(uintptr(unsafe.Pointer(acl)), 0, uintptr(unsafe.Pointer(&ace)))
	if ok == 0 || ace == nil || ace.Type != 0 || ace.Flags != 0 || ace.Size < 20 || ace.Mask != 0x1f01ff {
		return invalid
	}
	allowedSID, err := (*syscall.SID)(unsafe.Pointer(&ace.SID)).String()
	if err != nil || allowedSID != sid {
		return invalid
	}
	return nil
}

func openWindows(path string, create bool, directory bool) (*os.File, error) {
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	access, disposition := uint32(syscall.GENERIC_READ|0x20000), uint32(syscall.OPEN_EXISTING)
	var attributes *syscall.SecurityAttributes
	if create {
		var cleanup func()
		attributes, cleanup, err = privateAttributes()
		if err != nil {
			return nil, err
		}
		defer cleanup()
		access, disposition = syscall.GENERIC_WRITE|0x20000, syscall.CREATE_NEW
	}
	flags := uint32(syscall.FILE_FLAG_OPEN_REPARSE_POINT)
	if directory {
		flags |= syscall.FILE_FLAG_BACKUP_SEMANTICS
	}
	handle, err := syscall.CreateFile(p, access, syscall.FILE_SHARE_READ, attributes, disposition, flags, 0)
	runtime.KeepAlive(attributes)
	if err != nil {
		return nil, err
	}
	f := os.NewFile(uintptr(handle), path)
	if err := checkPrivateHandle(f); err != nil {
		f.Close()
		return nil, err
	}
	info, err := f.Stat()
	if err == nil && (info.IsDir() != directory || (!directory && !info.Mode().IsRegular())) {
		err = errors.New("invalid configuration file type")
	}
	if err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

func checkPrivateDir(dir string) error {
	f, err := openWindows(dir, false, true)
	if err != nil {
		return err
	}
	return f.Close()
}

func makePrivateDir(dir string) error {
	if err := os.MkdirAll(filepath.Dir(dir), 0700); err != nil {
		return err
	}
	p, err := syscall.UTF16PtrFromString(dir)
	if err != nil {
		return err
	}
	attributes, cleanup, err := privateAttributes()
	if err != nil {
		return err
	}
	defer cleanup()
	err = syscall.CreateDirectory(p, attributes)
	runtime.KeepAlive(attributes)
	if err != nil && err != syscall.ERROR_ALREADY_EXISTS {
		return err
	}
	return checkPrivateDir(dir)
}

func openPrivate(path string) (*os.File, error)   { return openWindows(path, false, false) }
func createPrivate(path string) (*os.File, error) { return openWindows(path, true, false) }

func installConfig(tmp, target string) error {
	from, err := syscall.UTF16PtrFromString(tmp)
	if err != nil {
		return err
	}
	to, err := syscall.UTF16PtrFromString(target)
	if err != nil {
		return err
	}
	// MoveFile is a same-directory rename and never replaces an existing file.
	return syscall.MoveFile(from, to)
}
