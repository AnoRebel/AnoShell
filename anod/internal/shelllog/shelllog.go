// Package shelllog reads the running shell's QML warnings and errors from
// Quickshell's own log ($XDG_RUNTIME_DIR/quickshell/by-pid/<pid>/log.log, a
// link into by-id/<instance>/). Stock Quickshell has no in-process API for
// its log, so anod reads the file for Settings → About → Errors and
// `ano doctor`.
package shelllog

import (
	"bufio"
	"errors"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"ano/anod/internal/config"
)

const (
	MaxEntries = 200     // distinct messages kept (the most recent)
	maxRead    = 8 << 20 // only the log's tail is read
	maxMsg     = 2000
)

// Entry is one distinct warning or error and how often it was logged.
type Entry struct {
	Level    string `json:"level"` // "WARN" or "ERROR"
	Category string `json:"category"`
	Message  string `json:"message"`
	Count    int    `json:"count"`
	First    string `json:"first"` // timestamps as the log writes them
	Last     string `json:"last"`
}

// Result is shell.errors' reply.
type Result struct {
	Log     string  `json:"log"`
	PID     int     `json:"pid"`
	Total   int     `json:"total"` // lines, duplicates included
	Errors  int     `json:"errors"`
	Entries []Entry `json:"entries"` // newest last
	Dropped int     `json:"dropped"` // distinct messages beyond MaxEntries
	Partial bool    `json:"partial"` // only the log's last 8 MiB were read
}

// "2026-11-10 02:04:06.021  WARN scene: …", the category optional.
var lineRe = regexp.MustCompile(`^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s+([A-Z]+)(?: ([\w.-]+))?: (.*)$`)

// shellCategory: QML and scene messages, which are the shell's own code
// (console.warn/error, binding and type errors); not Qt's or the
// compositor's chatter.
func shellCategory(c string) bool {
	return c == "qml" || c == "scene" || strings.HasPrefix(c, "qml.") || strings.HasPrefix(c, "scene.") || strings.HasPrefix(c, "qt.qml")
}

// Parse collects WARN/ERROR lines of the shell's categories, deduplicated by
// level, category and message; continuation lines join the message above.
func Parse(r io.Reader) Result {
	res := Result{Entries: []Entry{}}
	byKey := map[string]*Entry{}
	order := map[string]int{} // key -> last position
	var cur *Entry
	pos := 0
	finish := func() {
		if cur == nil {
			return
		}
		key := cur.Level + "\x00" + cur.Category + "\x00" + cur.Message
		if e, ok := byKey[key]; ok {
			e.Count++
			e.Last = cur.Last
		} else {
			byKey[key] = cur
		}
		order[key] = pos
		pos++
		res.Total++
		if cur.Level == "ERROR" {
			res.Errors++
		}
		cur = nil
	}
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		m := lineRe.FindStringSubmatch(line)
		if m == nil {
			if cur != nil && strings.TrimSpace(line) != "" && len(cur.Message) < maxMsg {
				cur.Message = clip(cur.Message + "\n" + strings.TrimRight(line, " \t"))
			}
			continue
		}
		finish()
		lvl := m[2]
		if lvl == "CRIT" || lvl == "FATAL" {
			lvl = "ERROR"
		}
		if (lvl != "WARN" && lvl != "ERROR") || !shellCategory(m[3]) {
			continue
		}
		cur = &Entry{Level: lvl, Category: m[3], Message: clip(m[4]), Count: 1, First: m[1], Last: m[1]}
	}
	finish()
	keys := make([]string, 0, len(byKey))
	for k := range byKey {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return order[keys[i]] < order[keys[j]] })
	if len(keys) > MaxEntries {
		res.Dropped = len(keys) - MaxEntries
		keys = keys[len(keys)-MaxEntries:]
	}
	for _, k := range keys {
		res.Entries = append(res.Entries, *byKey[k])
	}
	return res
}

func clip(s string) string {
	if len(s) <= maxMsg {
		return s
	}
	cut := maxMsg
	for cut > 0 && !utf8Start(s[cut]) {
		cut--
	}
	return s[:cut] + "…"
}

func utf8Start(b byte) bool { return b&0xC0 != 0x80 }

// Cmdline reads a process's arguments (a variable so tests can fake it).
var Cmdline = func(pid int) []string {
	b, err := os.ReadFile("/proc/" + strconv.Itoa(pid) + "/cmdline")
	if err != nil || len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimRight(string(b), "\x00"), "\x00")
}

// IsShell: argv runs AnoShell itself (qs -c ano, or -p the checkout), not
// the standalone Settings window or another config.
func IsShell(argv []string) bool {
	if len(argv) == 0 {
		return false
	}
	if b := filepath.Base(argv[0]); b != "qs" && b != "quickshell" {
		return false
	}
	dir := filepath.Clean(config.ShellDir())
	for i := 1; i < len(argv); i++ {
		a, v := argv[i], ""
		if k, val, ok := strings.Cut(a, "="); ok && strings.HasPrefix(k, "-") {
			a, v = k, val
		} else if i+1 < len(argv) {
			v = argv[i+1]
		}
		switch a {
		case "-c", "--config":
			if v == "ano" {
				return true
			}
		case "-p", "--path":
			if p := filepath.Clean(v); p == dir || p == filepath.Join(dir, "shell.qml") {
				return true
			}
		}
	}
	return false
}

func runtimeDir() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return d
	}
	return filepath.Join(os.TempDir(), "runtime-"+strconv.Itoa(os.Getuid()))
}

// Find is the running shell's log: pid's when that process is the shell
// (Settings in the shell passes its own), else the newest log of a running
// shell (the standalone Settings window is another process).
func Find(pid int) (string, int, error) {
	base := filepath.Join(runtimeDir(), "quickshell", "by-pid")
	logOf := func(p int) string {
		l := filepath.Join(base, strconv.Itoa(p), "log.log")
		if _, err := os.Stat(l); err != nil || !IsShell(Cmdline(p)) {
			return ""
		}
		return l
	}
	if pid > 0 {
		if l := logOf(pid); l != "" {
			return l, pid, nil
		}
	}
	ents, _ := os.ReadDir(base)
	best, bestPID := "", 0
	var bestMod int64
	for _, e := range ents {
		p, err := strconv.Atoi(e.Name())
		if err != nil || p == pid {
			continue
		}
		if l := logOf(p); l != "" {
			if fi, err := os.Stat(l); err == nil && fi.ModTime().UnixNano() > bestMod {
				best, bestPID, bestMod = l, p, fi.ModTime().UnixNano()
			}
		}
	}
	if best == "" {
		return "", 0, errors.New("no running AnoShell log found under " + base)
	}
	return best, bestPID, nil
}

// Errors finds the shell's log and parses its tail.
func Errors(pid int) (Result, error) {
	l, p, err := Find(pid)
	if err != nil {
		return Result{Entries: []Entry{}}, err
	}
	f, err := os.Open(l)
	if err != nil {
		return Result{Entries: []Entry{}}, err
	}
	defer f.Close()
	partial := false
	if fi, err := f.Stat(); err == nil && fi.Size() > maxRead {
		f.Seek(fi.Size()-maxRead, io.SeekStart)
		partial = true
	}
	res := Parse(f)
	res.Log, res.PID, res.Partial = l, p, partial
	return res, nil
}
