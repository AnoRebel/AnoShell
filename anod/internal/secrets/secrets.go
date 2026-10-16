// Package secrets keeps API keys (Wallhaven, …) out of config.json: one file
// per secret in $XDG_DATA_HOME/anoshell/secrets/<name>, mode 0600, in a 0700
// directory. The shell reads them; it writes them through anod (secret.set).
package secrets

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var nameRE = regexp.MustCompile(`^[a-z0-9_-]+$`)

// MaxSize bounds a secret's value.
const MaxSize = 16 << 10

// Dir is $XDG_DATA_HOME/anoshell/secrets (~/.local/share/… by default).
func Dir() string {
	d := os.Getenv("XDG_DATA_HOME")
	if d == "" {
		home, _ := os.UserHomeDir()
		d = filepath.Join(home, ".local", "share")
	}
	return filepath.Join(d, "anoshell", "secrets")
}

// Path is where the secret called name is kept.
func Path(name string) (string, error) {
	if !nameRE.MatchString(name) {
		return "", fmt.Errorf("bad secret name %q (want [a-z0-9_-]+)", name)
	}
	return filepath.Join(Dir(), name), nil
}

// Set stores value (surrounding whitespace trimmed) atomically with mode
// 0600; an empty value removes the secret.
func Set(name, value string) error {
	p, err := Path(name)
	if err != nil {
		return err
	}
	value = strings.TrimSpace(value)
	if len(value) > MaxSize {
		return fmt.Errorf("secret too large (%d bytes, max %d)", len(value), MaxSize)
	}
	dir := filepath.Dir(p)
	if value == "" {
		if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		return nil
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	if err := os.Chmod(dir, 0o700); err != nil { // tighten a directory made looser earlier
		return err
	}
	f, err := os.CreateTemp(dir, "."+name+".tmp-*") // CreateTemp makes it 0600
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp) // no-op after the rename
	if err := f.Chmod(0o600); err != nil {
		f.Close()
		return err
	}
	if _, err := f.WriteString(value); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, p)
}

// Get returns the secret, "" when it isn't set.
func Get(name string) (string, error) {
	p, err := Path(name)
	if err != nil {
		return "", err
	}
	b, err := os.ReadFile(p)
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	return strings.TrimSpace(string(b)), err
}
