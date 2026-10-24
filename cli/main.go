package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
)

const usage = `Selia Wake CLI | one target, no cloud, no background service

seliawake [--config-dir DIRECTORY] COMMAND [FLAGS]

init-waker --tailnet-ip IP --lan-ip IP --mac MAC [--broadcast IP] [--name NAME]
    Create a new Waker config and random secret. Never overwrites a config.
pair --stdin
    Read one secret pairing URI from stdin, then EOF. Never pass it as an argument.
export-pairing --show-secret
    Print the secret pairing URI. Anyone holding it can request wakes.
wake
    Send an authenticated request to the paired Waker through Tailscale.
send-local
    Send the configured magic packet from the configured physical LAN IPv4.
serve --allow-tailnet
    Run the Waker on its assigned Tailscale IPv4:45879 until Ctrl+C.
status
    Show local config without the secret. Does not probe a relay or target.
help
    Show this help.

Config contains a plaintext secret, protected by owner-only permissions/ACL.
Success means a UDP send completed, not that the target booted.
`

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	if err := run(ctx, os.Args[1:], os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

func parseFlags(f *flag.FlagSet, args []string) error {
	f.SetOutput(io.Discard)
	if err := f.Parse(args); err != nil || f.NArg() != 0 {
		// flag errors may contain secret arguments supplied by mistake.
		return errors.New("invalid arguments; run help, and never pass pairing secrets on the command line")
	}
	return nil
}

func run(ctx context.Context, args []string, in io.Reader, out io.Writer) error {
	if len(args) == 1 && (args[0] == "--help" || args[0] == "-h") {
		_, err := io.WriteString(out, usage)
		return err
	}
	global := flag.NewFlagSet("seliawake", flag.ContinueOnError)
	dir := global.String("config-dir", "", "configuration directory")
	global.SetOutput(io.Discard)
	if err := global.Parse(args); err != nil {
		return errors.New("invalid global options; run help")
	}
	args = global.Args()
	if len(args) == 0 || (len(args) == 1 && (args[0] == "help" || args[0] == "--help" || args[0] == "-h")) {
		_, err := io.WriteString(out, usage)
		return err
	}
	var err error
	if *dir == "" {
		*dir, err = defaultConfigDir()
		if err != nil {
			return err
		}
	}
	*dir, err = filepath.Abs(*dir)
	if err != nil {
		return err
	}
	f := flag.NewFlagSet("command", flag.ContinueOnError)
	switch args[0] {
	case "init-waker":
		host := f.String("tailnet-ip", "", "assigned Tailscale IPv4")
		lan := f.String("lan-ip", "", "physical LAN IPv4")
		mac := f.String("mac", "", "target unicast MAC")
		broadcast := f.String("broadcast", "255.255.255.255", "LAN broadcast IPv4")
		name := f.String("name", "Waker", "pairing name")
		if err := parseFlags(f, args[1:]); err != nil {
			return err
		}
		key, err := randomKey(32)
		if err != nil {
			return err
		}
		c := config{Role: "waker", Pairing: pairing{1, *host, key, *name}, LAN: *lan, Broadcast: *broadcast, MAC: *mac}
		if err := c.checkLAN(); err != nil {
			return err
		}
		if _, err := assignedInterface(*host); err != nil {
			return fmt.Errorf("Tailscale address: %w", err)
		}
		if err := saveConfig(*dir, c); err != nil {
			return err
		}
		fmt.Fprintln(out, "Waker configuration saved. Secret stays in the protected config.")
		return nil
	case "pair":
		stdin := f.Bool("stdin", false, "read pairing from stdin")
		if err := parseFlags(f, args[1:]); err != nil {
			return err
		}
		if !*stdin {
			return errors.New("pair requires --stdin; paste the secret URI, then EOF")
		}
		code, err := io.ReadAll(io.LimitReader(in, 2049))
		if err != nil {
			return errors.New("cannot read pairing from stdin")
		}
		p, err := parsePairing(string(code))
		if err != nil {
			return err
		}
		if err := saveConfig(*dir, config{Role: "user", Pairing: p}); err != nil {
			return err
		}
		fmt.Fprintln(out, "Pairing saved. The secret is not displayed.")
		return nil
	case "export-pairing":
		show := f.Bool("show-secret", false, "explicitly reveal pairing secret")
		if err := parseFlags(f, args[1:]); err != nil {
			return err
		}
		if !*show {
			return errors.New("export requires --show-secret; the URI grants wake access")
		}
		c, err := loadConfig(*dir)
		if err != nil {
			return err
		}
		code, err := c.Pairing.encode()
		if err == nil {
			_, err = fmt.Fprintln(out, code)
		}
		return err
	case "wake", "send-local", "serve", "status":
		allow := false
		if args[0] == "serve" {
			f.BoolVar(&allow, "allow-tailnet", false, "allow authenticated tailnet requests")
		}
		if err := parseFlags(f, args[1:]); err != nil {
			return err
		}
		if args[0] == "serve" && !allow {
			return errors.New("serve requires --allow-tailnet; restrict TCP 45879 using Tailscale policy")
		}
		c, err := loadConfig(*dir)
		if err != nil {
			return err
		}
		switch args[0] {
		case "status":
			// Quoting escapes terminal controls in names and paths.
			fmt.Fprintf(out, "Role: %s\nName: %q\nTailscale IPv4: %s\nConfig directory: %q\nSecret: hidden\n", c.Role, c.Pairing.Name, c.Pairing.Host, *dir)
			if c.Role == "waker" {
				fmt.Fprintf(out, "LAN IPv4: %s\nBroadcast: %s\nTarget MAC: %s\n", c.LAN, c.Broadcast, c.MAC)
			}
			fmt.Fprintln(out, "This shows saved configuration only. Relay and target state are unknown.")
			return nil
		case "serve":
			return serve(ctx, c, out)
		case "wake":
			client := newWakeClient()
			defer client.CloseIdleConnections()
			err = requestWake(ctx, c.Pairing, client)
		case "send-local":
			err = sendLocal(c)
		}
		if err == nil {
			fmt.Fprintln(out, "Magic packet sent. Target boot is not confirmed.")
		}
		return err
	default:
		return errors.New("unknown command; run help")
	}
}
