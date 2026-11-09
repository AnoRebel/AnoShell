package supervisor

import (
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"testing"
)

// The child sees the raised soft limit (not the 1024 a compositor hands out).
func TestRaiseNoFileReachesChild(t *testing.T) {
	var r syscall.Rlimit
	if err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &r); err != nil {
		t.Skip(err)
	}
	orig := r
	r.Cur = min(uint64(1024), r.Max)
	if err := syscall.Setrlimit(syscall.RLIMIT_NOFILE, &r); err != nil {
		t.Skip(err)
	}
	defer syscall.Setrlimit(syscall.RLIMIT_NOFILE, &orig)
	raiseNoFile()
	out, err := exec.Command("sh", "-c", "ulimit -Sn").Output()
	if err != nil {
		t.Fatal(err)
	}
	got, _ := strconv.ParseUint(strings.TrimSpace(string(out)), 10, 64)
	if want := min(uint64(65536), orig.Max); got != want {
		t.Fatalf("child soft limit %d, want %d", got, want)
	}
}
