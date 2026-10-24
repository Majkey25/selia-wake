//go:build linux || darwin

package main

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
)

func checkOwner(info os.FileInfo) error {
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != uint32(os.Getuid()) || info.Mode().Perm()&0077 != 0 {
		return errors.New("configuration must be owner-only and owned by the current user")
	}
	return nil
}

func checkPrivateDir(dir string) error {
	info, err := os.Lstat(dir)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return errors.New("configuration directory must be a real directory")
	}
	return checkOwner(info)
}

func makePrivateDir(dir string) error {
	if err := os.MkdirAll(filepath.Dir(dir), 0700); err != nil {
		return err
	}
	if err := os.Mkdir(dir, 0700); err != nil && !os.IsExist(err) {
		return err
	}
	return checkPrivateDir(dir)
}

func openPrivate(path string) (*os.File, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("configuration must be a regular file, not a link")
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	actual, err := f.Stat()
	if err == nil && !os.SameFile(info, actual) {
		err = errors.New("configuration changed while opening")
	}
	if err == nil {
		err = checkOwner(actual)
	}
	if err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

func createPrivate(path string) (*os.File, error) {
	return os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
}

func installConfig(tmp, target string) error {
	// Linking is atomic and refuses to replace a concurrent creator's config.
	if err := os.Link(tmp, target); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(target))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
