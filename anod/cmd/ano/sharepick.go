package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	"ano/anod/internal/config"
)

// The screen-share picker: xdg-desktop-portal-hyprland runs its
// custom_picker_binary (scripts/share-picker → `ano share-pick`) when an app
// asks to share the screen. The choices come in XDPH_* environment variables,
// the answer goes out as one `[SELECTION]<flags>/<choice>` line on stdout;
// nothing printed means "cancelled". Protocol: xdph src/shared/ScreencopyShared.cpp
// (buildWindowList, buildOutputList, parsePickerSelection) and
// hyprland-share-picker/PickerData.cpp (formatSelection), v1.5.0.
//
// The shell shows the picker (modules/sharePicker) and writes its answer to a
// file in a private runtime folder; when the shell can't take the request the
// stock hyprland-share-picker runs instead, with the same environment.

type shareWindow struct {
	ID      uint32 `json:"id"` // the portal's handle (low 32 bits of the toplevel resource)
	Class   string `json:"class"`
	Title   string `json:"title"`
	Address string `json:"address"` // Hyprland window address, "0x…" ("" when unknown)
}

type shareOutput struct {
	Name string `json:"name"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
	W    int    `json:"w"`
	H    int    `json:"h"`
}

type shareRequest struct {
	ID         string        `json:"id"`
	Reply      string        `json:"reply"` // where the shell writes {"choice","restore"}
	AllowToken bool          `json:"allowToken"`
	Windows    []shareWindow `json:"windows"`
	Outputs    []shareOutput `json:"outputs"`
}

// parseShareWindows reads XDPH_WINDOW_SHARING_LIST:
// <id>[HC>]<class>[HT>]<title>[HE>]<address, decimal>[HA>] repeated.
func parseShareWindows(list string) []shareWindow {
	var out []shareWindow
	for list != "" {
		var f [4]string
		ok := true
		for i, sep := range []string{"[HC>]", "[HT>]", "[HE>]", "[HA>]"} {
			v, rest, found := strings.Cut(list, sep)
			if !found {
				ok = false
				break
			}
			f[i], list = v, rest
		}
		if !ok {
			break
		}
		id, err := strconv.ParseUint(f[0], 10, 32)
		if err != nil {
			continue
		}
		w := shareWindow{ID: uint32(id), Class: f[1], Title: f[2]}
		if a, err := strconv.ParseUint(f[3], 10, 64); err == nil && a != 0 {
			w.Address = fmt.Sprintf("0x%x", a)
		}
		out = append(out, w)
	}
	return out
}

// parseShareOutputs reads XDPH_OUTPUT_SHARING_LIST:
// <name length>:<name>:<x>:<y>:<w>:<h>; repeated (lengths in bytes).
func parseShareOutputs(list string) []shareOutput {
	var out []shareOutput
	for list != "" {
		n, rest, ok := strings.Cut(list, ":")
		size, err := strconv.Atoi(n)
		if !ok || err != nil || size <= 0 || size > len(rest) {
			break
		}
		name := rest[:size]
		rest = rest[size:]
		if !strings.HasPrefix(rest, ":") {
			break
		}
		fields, tail, ok := strings.Cut(rest[1:], ";")
		if !ok {
			break
		}
		list = tail
		parts := strings.Split(fields, ":")
		if len(parts) != 4 {
			continue
		}
		var v [4]int
		bad := false
		for i, p := range parts {
			if v[i], err = strconv.Atoi(p); err != nil {
				bad = true
			}
		}
		if bad || v[2] <= 0 || v[3] <= 0 {
			continue
		}
		out = append(out, shareOutput{name, v[0], v[1], v[2], v[3]})
	}
	return out
}

var regionChoice = regexp.MustCompile(`^region:([^@\s/]+)@(\d+),(\d+),(\d+),(\d+)$`)

// selectionLine checks the shell's choice against what the portal offered and
// formats the line the portal reads ("" and an error when it doesn't fit).
func selectionLine(req shareRequest, choice string, restore bool) (string, error) {
	knownOutput := func(name string) bool {
		if name == "" || strings.ContainsAny(name, "\r\n") {
			return false
		}
		// An xdph without the output list: the portal checks the name itself.
		return len(req.Outputs) == 0 || slices.ContainsFunc(req.Outputs, func(o shareOutput) bool { return o.Name == name })
	}
	ok := false
	switch {
	case strings.HasPrefix(choice, "screen:"):
		ok = knownOutput(choice[7:])
	case strings.HasPrefix(choice, "window:"):
		id, err := strconv.ParseUint(choice[7:], 10, 32)
		ok = err == nil && slices.ContainsFunc(req.Windows, func(w shareWindow) bool { return w.ID == uint32(id) })
	case strings.HasPrefix(choice, "region:"):
		if m := regionChoice.FindStringSubmatch(choice); m != nil && knownOutput(m[1]) {
			w, _ := strconv.ParseUint(m[4], 10, 31)
			h, _ := strconv.ParseUint(m[5], 10, 31)
			_, ex := strconv.ParseUint(m[2], 10, 31)
			_, ey := strconv.ParseUint(m[3], 10, 31)
			ok = w > 0 && h > 0 && ex == nil && ey == nil
		}
	}
	if !ok {
		return "", fmt.Errorf("not something the portal offered: %q", choice)
	}
	flags := ""
	if restore {
		flags = "r"
	}
	return "[SELECTION]" + flags + "/" + choice, nil
}

// Swapped out by the tests.
var (
	sharePickTimeout  = 60 * time.Second
	sharePickPoll     = 100 * time.Millisecond
	sharePickAlive    = 2 * time.Second
	sharePickShell    = shellCall
	sharePickFallback = execStockPicker
)

func sharePickCmd(args []string) int {
	if len(args) > 0 {
		switch args[0] {
		case "install":
			return sharePickInstall(args[1:])
		case "status":
			st, cur := xdphPickerStatus(xdphConfPath(), defaultPickerPath())
			fmt.Println(st, cur)
			return 0
		case "help", "-h", "--help":
			fmt.Println("usage: ano share-pick [--allow-token]       (run by xdg-desktop-portal-hyprland)\n       ano share-pick status | install [--picker PATH] [--dry-run]")
			return 0
		}
	}
	line, err := sharePick(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano share-pick:", err)
		return sharePickFallback(args)
	}
	if line != "" {
		fmt.Println(line)
	}
	return 0
}

// errShellGone: the shell didn't take the request or dropped it (a reload).
var errShellGone = errors.New("the shell isn't showing the picker")

// sharePick asks the shell and waits for its answer: the selection line, ""
// for cancelled, or errShellGone (→ the stock picker).
func sharePick(args []string) (string, error) {
	runtime := os.Getenv("XDG_RUNTIME_DIR")
	if runtime == "" {
		runtime = os.TempDir()
	}
	dir, err := os.MkdirTemp(runtime, "ano-share-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(dir)
	req := shareRequest{
		ID:         filepath.Base(dir),
		Reply:      filepath.Join(dir, "reply"),
		AllowToken: slices.Contains(args, "--allow-token"),
		Windows:    parseShareWindows(os.Getenv("XDPH_WINDOW_SHARING_LIST")),
		Outputs:    parseShareOutputs(os.Getenv("XDPH_OUTPUT_SHARING_LIST")),
	}
	b, _ := json.Marshal(req)
	if res, err := sharePickShell("sharePicker", "pick", string(b)); err != nil || res != "ok" {
		return "", fmt.Errorf("%w (%v %s)", errShellGone, err, res)
	}
	deadline := time.Now().Add(sharePickTimeout)
	lastAlive := time.Now()
	for time.Now().Before(deadline) {
		time.Sleep(sharePickPoll)
		if data, err := os.ReadFile(req.Reply); err == nil {
			var r struct {
				Choice  string `json:"choice"`
				Restore bool   `json:"restore"`
			}
			if err := json.Unmarshal(data, &r); err != nil {
				return "", fmt.Errorf("bad reply: %v", err)
			}
			if r.Choice == "" {
				return "", nil // cancelled
			}
			return selectionLine(req, r.Choice, r.Restore)
		}
		if time.Since(lastAlive) >= sharePickAlive {
			lastAlive = time.Now()
			if res, _ := sharePickShell("sharePicker", "pending", req.ID); res != "yes" {
				if _, err := os.Stat(req.Reply); err == nil {
					continue // answered just now
				}
				return "", errShellGone
			}
		}
	}
	sharePickShell("sharePicker", "cancel", req.ID)
	fmt.Fprintln(os.Stderr, "ano share-pick: no choice in time")
	return "", nil
}

// execStockPicker replaces this process with hyprland-share-picker, which
// reads the same environment and prints the same line.
func execStockPicker(args []string) int {
	bin, err := exec.LookPath("hyprland-share-picker")
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano share-pick: hyprland-share-picker not found; nothing shared")
		return 1
	}
	err = syscall.Exec(bin, append([]string{"hyprland-share-picker"}, args...), os.Environ())
	fmt.Fprintln(os.Stderr, "ano share-pick:", err)
	return 1
}

// ── xdph.conf ───────────────────────────────────────────────────────────────

func xdphConfPath() string {
	d := os.Getenv("XDG_CONFIG_HOME")
	if d == "" {
		h, _ := os.UserHomeDir()
		d = filepath.Join(h, ".config")
	}
	return filepath.Join(d, "hypr", "xdph.conf")
}

func defaultPickerPath() string { return filepath.Join(config.ShellDir(), "scripts", "share-picker") }

// custom_picker_binary, in a screencopy { } block or as screencopy:custom_picker_binary.
var pickerLine = regexp.MustCompile(`^(\s*(?:screencopy:)?custom_picker_binary\s*=)\s*(.*?)\s*$`)
var screencopyOpen = regexp.MustCompile(`^\s*screencopy\s*\{\s*(#.*)?$`)

// currentPicker returns the custom_picker_binary value set in conf ("" when unset).
func currentPicker(conf string) string {
	cur := ""
	for _, l := range strings.Split(conf, "\n") {
		if m := pickerLine.FindStringSubmatch(l); m != nil {
			v, _, _ := strings.Cut(m[2], "#") // an end-of-line comment
			cur = strings.TrimSpace(v)        // the last one wins, as in hyprlang
		}
	}
	return cur
}

// xdphPickerStatus: "ano" (our picker), "other" (another one), "stock" (unset)
// or "missing" (no xdph.conf), with the current value.
func xdphPickerStatus(path, picker string) (string, string) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "missing", ""
	}
	switch cur := currentPicker(string(b)); {
	case cur == "":
		return "stock", ""
	case cur == picker || sameFile(cur, picker):
		return "ano", cur
	default:
		return "other", cur
	}
}

func sameFile(a, b string) bool {
	fa, err1 := os.Stat(a)
	fb, err2 := os.Stat(b)
	return err1 == nil && err2 == nil && os.SameFile(fa, fb)
}

// setPicker returns conf with custom_picker_binary set to picker: the existing
// line is rewritten, else the line goes into the screencopy block, else a
// block is appended.
func setPicker(conf, picker string) string {
	lines := strings.Split(conf, "\n")
	last := -1
	for i, l := range lines {
		if pickerLine.MatchString(l) {
			last = i
		}
	}
	if last >= 0 {
		lines[last] = pickerLine.ReplaceAllString(lines[last], "${1} "+strings.ReplaceAll(picker, "$", "$$"))
		return strings.Join(lines, "\n")
	}
	for i, l := range lines {
		if screencopyOpen.MatchString(l) {
			ins := "    custom_picker_binary = " + picker
			return strings.Join(slices.Insert(lines, i+1, ins), "\n")
		}
	}
	if conf != "" && !strings.HasSuffix(conf, "\n") {
		conf += "\n"
	}
	if conf != "" {
		conf += "\n"
	}
	return conf + "screencopy {\n    custom_picker_binary = " + picker + "\n}\n"
}

// sharePickInstall writes custom_picker_binary into xdph.conf, after a backup.
func sharePickInstall(args []string) int {
	picker, dry := defaultPickerPath(), false
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--dry-run":
			dry = true
		case "--picker":
			if i+1 < len(args) {
				picker = args[i+1]
				i++
			}
		}
	}
	if !filepath.IsAbs(picker) || strings.ContainsAny(picker, "#\r\n") {
		fmt.Fprintf(os.Stderr, "ano share-pick: %q must be an absolute path without # or newlines\n", picker)
		return 2
	}
	if fi, err := os.Stat(picker); err != nil || fi.Mode()&0o111 == 0 {
		fmt.Fprintf(os.Stderr, "ano share-pick: %s is not an executable file\n", picker)
		return 1
	}
	path := xdphConfPath()
	if real, err := filepath.EvalSymlinks(path); err == nil {
		path = real // a dotfiles symlink stays a symlink
	}
	old, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		fmt.Fprintln(os.Stderr, "ano share-pick:", err)
		return 1
	}
	next := setPicker(string(old), picker)
	if next == string(old) {
		fmt.Println("already set:", path)
		return 0
	}
	if dry {
		fmt.Print(next)
		return 0
	}
	if len(old) > 0 {
		bak := path + ".bak-" + time.Now().Format("20060102-150405")
		if err := os.WriteFile(bak, old, 0o644); err != nil {
			fmt.Fprintln(os.Stderr, "ano share-pick: backup:", err)
			return 1
		}
		fmt.Println("backup:", bak)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		fmt.Fprintln(os.Stderr, "ano share-pick:", err)
		return 1
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(next), 0o644); err != nil || os.Rename(tmp, path) != nil {
		os.Remove(tmp)
		fmt.Fprintln(os.Stderr, "ano share-pick: could not write", path)
		return 1
	}
	fmt.Println("wrote:", path, "(restart xdg-desktop-portal-hyprland to use it)")
	return 0
}
