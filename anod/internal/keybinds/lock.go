package keybinds

import (
	"os"
	"path/filepath"
	"syscall"
)

// Lock takes an exclusive advisory lock beside keybinds.json, so anod
// (Settings, Atelier rices) and the ano CLI don't interleave a
// read-change-write and lose each other's change. Hold it from the read
// through Generate; call the returned func to release.
func Lock(p Paths) (func(), error) {
	path := p.Overrides + ".lock"
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return func() { syscall.Flock(int(f.Fd()), syscall.LOCK_UN); f.Close() }, nil
}
