package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"path/filepath"
)

type config struct {
	Role      string  `json:"role"`
	Pairing   pairing `json:"pairing"`
	LAN       string  `json:"lan,omitempty"`
	Broadcast string  `json:"broadcast,omitempty"`
	MAC       string  `json:"mac,omitempty"`
}

func defaultConfigDir() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "seliawake-cli"), nil
}

func (c config) validate() error {
	if err := c.Pairing.validate(); err != nil {
		return err
	}
	switch c.Role {
	case "user":
		if c.LAN != "" || c.Broadcast != "" || c.MAC != "" {
			return errors.New("invalid_user_config")
		}
	case "waker":
		if !isLAN(c.LAN) || (c.Broadcast != "255.255.255.255" && !isLAN(c.Broadcast)) {
			return errors.New("invalid_lan_config")
		}
		if _, err := magicPacket(c.MAC); err != nil {
			return err
		}
	default:
		return errors.New("invalid_role")
	}
	return nil
}

func isLAN(s string) bool {
	ip, err := netip.ParseAddr(s)
	return err == nil && ip.Is4() && ip.IsPrivate()
}

// Inspect only local interface assignments. Do not probe the network.
func assignedInterface(address string) (*net.IPNet, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addresses, err := iface.Addrs()
		if err != nil {
			return nil, err
		}
		for _, addr := range addresses {
			ip, ok := addr.(*net.IPNet)
			if ok && ip.IP.To4() != nil && ip.IP.String() == address {
				return ip, nil
			}
		}
	}
	return nil, errors.New("configured IP is not assigned to an active local interface")
}

func (c config) checkLAN() error {
	if c.Role != "waker" {
		return errors.New("this command requires a Waker configuration")
	}
	if err := c.validate(); err != nil {
		return err
	}
	lan, err := assignedInterface(c.LAN)
	if err != nil {
		return err
	}
	ip := lan.IP.To4()
	mask := lan.Mask
	ones, bits := mask.Size()
	if bits != 32 || ones > 30 {
		return errors.New("LAN needs an IPv4 broadcast subnet")
	}
	broadcast := net.IPv4(ip[0]|^mask[0], ip[1]|^mask[1], ip[2]|^mask[2], ip[3]|^mask[3]).String()
	if c.LAN == broadcast || c.LAN == ip.Mask(mask).String() {
		return errors.New("LAN source must be a host address")
	}
	if c.Broadcast != "255.255.255.255" && c.Broadcast != broadcast {
		return errors.New("broadcast must match the configured LAN subnet or 255.255.255.255")
	}
	return nil
}

func loadConfig(dir string) (config, error) {
	var c config
	if err := checkPrivateDir(dir); err != nil {
		return c, err
	}
	f, err := openPrivate(filepath.Join(dir, "config.json"))
	if err != nil {
		return c, err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, 4097))
	if err != nil || len(b) > 4096 {
		return c, errors.New("cannot read bounded configuration")
	}
	if _, err := jsonObject(b); err != nil {
		return c, errors.New("invalid_config")
	}
	// Disallow fields that might imply unsupported behavior or hidden destinations.
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	if err := d.Decode(&c); err != nil {
		return config{}, errors.New("invalid_config")
	}
	return c, c.validate()
}

func saveConfig(dir string, c config) error {
	if err := c.validate(); err != nil {
		return err
	}
	if err := makePrivateDir(dir); err != nil {
		return err
	}
	name, err := randomKey(16)
	if err != nil {
		return err
	}
	tmp := filepath.Join(dir, ".config-"+name)
	f, err := createPrivate(tmp)
	if err != nil {
		return err
	}
	defer os.Remove(tmp)
	defer f.Close()
	if err := json.NewEncoder(f).Encode(c); err != nil {
		return err
	}
	if err := f.Sync(); err != nil {
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	if err := installConfig(tmp, filepath.Join(dir, "config.json")); err != nil {
		return fmt.Errorf("configuration was not installed; existing files are never replaced: %w", err)
	}
	return nil
}
