package supervisor

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func fast(cmd ...string) *Supervisor {
	return &Supervisor{Cmd: cmd, BaseDelay: time.Millisecond, MaxDelay: 5 * time.Millisecond}
}

func TestCrashLoopStops(t *testing.T) {
	var notified []string
	s := fast("sh", "-c", "exit 3")
	s.Notify = func(title, body string) { notified = append(notified, title+"|"+body) }
	s.CrashReport = func(time.Time) string { return "/tmp/crash-42" }
	if got := s.Run(context.Background()); got != CrashLoop {
		t.Fatalf("state = %s, want crash-loop", got)
	}
	st := s.Status()
	if st.Restarts != 4 || st.Recent != 5 {
		t.Errorf("restarts=%d recent=%d, want 4 and 5", st.Restarts, st.Recent)
	}
	if st.LastCrash != "/tmp/crash-42" || st.LastExit != "exit status 3" {
		t.Errorf("status = %+v", st)
	}
	if len(notified) != 1 || !strings.Contains(notified[0], "/tmp/crash-42") {
		t.Errorf("notify = %v", notified)
	}
}

func TestCrashesOutsideWindowDontCount(t *testing.T) {
	// The child crashes on its first two runs, then exits cleanly.
	n := filepath.Join(t.TempDir(), "n")
	script := `c=$(cat "$1" 2>/dev/null || echo 0); echo $((c+1)) > "$1"; [ "$c" -ge 2 ]`
	s := fast("sh", "-c", script, "sh", n)
	s.Window = time.Nanosecond // every earlier crash has expired by the next one
	s.MaxCrashes = 2
	if got := s.Run(context.Background()); got != Stopped {
		t.Fatalf("state = %s, want stopped", got)
	}
	if s.Status().Restarts != 2 {
		t.Errorf("restarts = %d, want 2", s.Status().Restarts)
	}
}

func TestCleanExitIsNotRestarted(t *testing.T) {
	s := fast("true")
	if got := s.Run(context.Background()); got != Stopped || s.Status().Restarts != 0 {
		t.Errorf("state=%s restarts=%d", got, s.Status().Restarts)
	}
}

func TestCancelStopsChildGroup(t *testing.T) {
	pidFile := filepath.Join(t.TempDir(), "pid")
	// A grandchild in the same process group must die too.
	s := fast("sh", "-c", `sleep 30 & echo $! > "$1"; wait`, "sh", pidFile)
	ctx, cancel := context.WithCancel(context.Background())
	res := make(chan State)
	go func() { res <- s.Run(ctx) }()
	for i := 0; i < 100 && s.Status().State != Running; i++ {
		time.Sleep(10 * time.Millisecond)
	}
	time.Sleep(100 * time.Millisecond)
	cancel()
	if got := <-res; got != Stopped {
		t.Fatalf("state = %s", got)
	}
	b, _ := os.ReadFile(pidFile)
	pid := strings.TrimSpace(string(b))
	time.Sleep(50 * time.Millisecond)
	if _, err := os.Stat("/proc/" + pid); err == nil {
		st, _ := os.ReadFile("/proc/" + pid + "/stat")
		if !strings.Contains(string(st), ") Z ") {
			t.Errorf("grandchild %s still alive", pid)
		}
	}
}

func TestNewestEntry(t *testing.T) {
	d := t.TempDir()
	if NewestEntry(d) != "" {
		t.Error("empty dir")
	}
	os.Mkdir(filepath.Join(d, "old"), 0o755)
	os.Chtimes(filepath.Join(d, "old"), time.Now().Add(-time.Hour), time.Now().Add(-time.Hour))
	os.Mkdir(filepath.Join(d, "new"), 0o755)
	if got := NewestEntry(d); filepath.Base(got) != "new" {
		t.Errorf("newest = %s", got)
	}
}

func TestNoRestartAfterSessionEnds(t *testing.T) {
	var notified bool
	s := fast("sh", "-c", "exit 1")
	s.Notify = func(string, string) { notified = true }
	s.Alive = func() bool { return false }
	if got := s.Run(context.Background()); got != Stopped || s.Status().Restarts != 0 || notified {
		t.Errorf("state=%s restarts=%d notified=%v", got, s.Status().Restarts, notified)
	}
}

func TestQuickshellCrashReportIgnoresOldReports(t *testing.T) {
	d := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", d)
	dir := filepath.Join(d, "quickshell", "crashes", "old")
	os.MkdirAll(dir, 0o755)
	os.Chtimes(dir, time.Now().Add(-time.Hour), time.Now().Add(-time.Hour))
	if got := QuickshellCrashReport(time.Now().Add(-time.Minute)); got != "" {
		t.Errorf("old report returned: %s", got)
	}
	if got := QuickshellCrashReport(time.Now().Add(-2 * time.Hour)); filepath.Base(got) != "old" {
		t.Errorf("report = %q", got)
	}
}

// The shell starts with transparent huge pages off.
func TestNoHugePagesReachesChild(t *testing.T) {
	s := fast("sh", "-c", `grep -Eq '^THP_enabled:[[:space:]]+0$' /proc/self/status`)
	s.NoHugePages = true
	s.MaxCrashes = 1
	if got := s.Run(context.Background()); got != Stopped {
		t.Fatalf("state = %s: the child still has huge pages on", got)
	}
}
