package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/ipc"
	"ano/anod/internal/supervisor"
)

// feature: binaries the shell spawns for it, checked when When is true.
type feature struct {
	Name string
	When string // config bool path that enables it (a|b: any of them); "" = always on
	Bins []string
}

// Built from the binaries the shell actually spawns (grep of modules/ services/ scripts/).
var features = []feature{
	{"notifications from scripts", "", []string{"notify-send"}},
	{"network panel", "", []string{"nmcli"}},
	{"watchers (nmcli monitor, wlsunset, cava, udevadm) end with the shell", "", []string{"setpriv"}},
	{"clipboard history", "", []string{"cliphist", "wl-copy"}},
	{"wallpaper + dynamic colours", "", []string{"awww", "matugen"}},
	{"Theme studio (schemes from your own colours)", "", []string{"matugen"}},
	{"launcher calculator", "search.plugins.calculator.enable", []string{"qalc"}},
	{"launcher package search", "search.plugins.packages.enable", []string{"paru|yay"}},
	{"translator (else AI fallback)", "", []string{"trans"}},
	{"screen recording", "", []string{"gpu-screen-recorder|wl-screenrec|wf-recorder"}},
	{"recording extras (finish thumbnail, discard to trash, system + mic mix)", "", []string{"ffmpeg", "gio", "pactl"}},
	{"screenshots (Hyprland and other wlroots; niri uses its own)", "", []string{"grim", "slurp"}},
	{"text recognition (Super+Shift+X; language data: tesseract-data-*)", "", []string{"tesseract"}},
	{"scratchpad (copy, failed-command notices)", "scratchpad.enable", []string{"wl-copy", "notify-send"}},
	{"brightness", "", []string{"brightnessctl"}},
	{"audio spectrum", "", []string{"cava"}},
	{"sound effects and battery sounds", "sounds.battery|sounds.login|sounds.notifications|sounds.panels|sounds.alerts", []string{"pw-play"}},
	{"startup applications (anod; else setsid)", "", []string{"systemd-run|setsid"}},
	{"weather", "bar.weather.enable", []string{"curl"}},
	{"public holidays", "calendar.holidays.enable", []string{"curl"}},
	{"calendar sync", "calendar.externalSync.enable", []string{"curl"}},
	{"VPN (NetBird)", "vpn.enable", []string{"netbird"}},
	{"KDE Connect (kdeconnectd must be running; file picker: zenity)", "kdeConnect.enable", []string{"kdeconnectd", "busctl", "gdbus", "setpriv"}},
	{"lock screen fingerprint (also needs an enrolled print: fprintd-enroll)", "lock.fingerprint.enable", []string{"fprintd-list"}},
	{"device event pills: USB", "deviceEvents.usb", []string{"udevadm", "setpriv"}},
	{"music recognition", "musicRecognition.enable", []string{"songrec", "pw-record", "notify-send", "wl-copy"}},
	{"package updates (bar module updates)", "updates.enable", []string{"checkupdates"}},
	{"EasyEffects quick toggle and presets", "audio.easyEffects.enable", []string{"easyeffects"}},
	{"game mode (and performance mode during games)", "gameMode.enable", []string{"gamemoded", "dbus-monitor", "busctl"}},
	{"night light", "nightLight.enable", []string{"wlsunset"}},
	{"location by IP address (automatic, when GeoClue gives nothing; GeoClue itself is the geoclue package)", "location.enable", []string{"curl"}},
	{"Bioma organism pieces (weather: curl; media band: cava; disks: df)", "pieces.enable", []string{"curl", "cava", "df"}},
	{"opening files and folders (downloads, drives)", "", []string{"xdg-open"}},
	{"actions: open-file/URL and shell-command steps", "", []string{"xdg-open", "sh"}},
	{"Qt apps in the palette (the qt6ct platform theme; kvantum for appearance.theme.qt \"kvantum\")", "", []string{"qt6ct"}},
	{"focus time", "focusTime.enable", []string{"python3"}},
	{"power profile restore", "powerProfiles.restoreOnStart", []string{"powerprofilesctl"}},
	{"anime reader playback", "reader.enable", []string{"mpv"}},
	{"keybinds: cheatsheet and migration (reads Lua configs)", "", []string{"lua"}},
	{"apps in their own session (else systemd-run)", "", []string{"setsid"}},
	{"password prompt (polkit) details", "polkit.enable", []string{"pkaction", "pgrep", "ps"}},
	{"removable drives (bar module drives)", "", []string{"udisksctl", "lsblk", "udevadm"}},
	{"lock screen on niri: locking on loginctl lock-session", "lock.enable", []string{"gdbus"}},
	{"launcher plugin clipboard history (bundled)", "", []string{"cliphist"}},
	{"launcher plugin files (bundled)", "", []string{"fd"}},
	{"launcher plugins kaomoji, unicode, keybinds (bundled; copy)", "", []string{"wl-copy"}},
}

// Other wallpaper rotators fight anod/awww over the wallpaper.
var rotators = []string{"awww_randomize", "swww_randomize", "wpaperd", "variety", "waypaper"}

type check struct {
	Level string `json:"level"` // ok | info | warn | fail
	Name  string `json:"name"`
	Msg   string `json:"message"`
}

func doctor(args []string) int {
	fs := flag.NewFlagSet("doctor", flag.ExitOnError)
	asJSON := fs.Bool("json", false, "machine-readable output")
	fs.Parse(args)
	checks := runChecks()
	failed := false
	for _, c := range checks {
		failed = failed || c.Level == "fail"
	}
	if *asJSON {
		b, _ := json.MarshalIndent(checks, "", "  ")
		fmt.Println(string(b))
	} else {
		for _, c := range checks {
			fmt.Printf("%-4s  %-28s %s\n", strings.ToUpper(c.Level), c.Name, c.Msg)
		}
	}
	if failed {
		return 1
	}
	return 0
}

// anyBool: one of the |-separated bool paths is true.
func anyBool(m map[string]any, paths string) bool {
	for _, p := range strings.Split(paths, "|") {
		if config.Bool(m, p, false) {
			return true
		}
	}
	return false
}

// have reports whether bin is on PATH ("a|b": either).
func have(bin string) bool {
	for _, b := range strings.Split(bin, "|") {
		if _, err := exec.LookPath(b); err == nil {
			return true
		}
	}
	return false
}

// experimentalBackend picks sway, mango or labwc in CompositorService's
// order: the desktop name, then the session's own variables, SWAYSOCK last
// (sway exports it, and labwc LABWC_PID, to the activation environment, so a
// later session of another compositor can inherit them).
func experimentalBackend() (name, bin string) {
	label := map[string][2]string{
		"sway":  {"sway (experimental)", "swaymsg"}, // tree and keyboard layouts
		"mango": {"mango (experimental)", ""},       // its socket; no binary needed
		"labwc": {"labwc (experimental)", "labwc"},  // labwc --exit
	}
	pick := ""
	for _, d := range []string{"sway", "mango", "labwc"} {
		if desktopIs(d) {
			pick = d
			break
		}
	}
	switch {
	case pick != "":
	case os.Getenv("MANGO_INSTANCE_SIGNATURE") != "":
		pick = "mango"
	case os.Getenv("LABWC_PID") != "":
		pick = "labwc"
	case os.Getenv("SWAYSOCK") != "":
		pick = "sway"
	default:
		return "generic (experimental)", ""
	}
	return label[pick][0], label[pick][1]
}

// desktopIs reports whether XDG_CURRENT_DESKTOP (colon-separated) names d.
func desktopIs(d string) bool {
	for _, x := range strings.Split(strings.ToLower(os.Getenv("XDG_CURRENT_DESKTOP")), ":") {
		if x == d {
			return true
		}
	}
	return false
}

func runChecks() []check {
	var out []check
	add := func(level, name, format string, a ...any) {
		out = append(out, check{level, name, fmt.Sprintf(format, a...)})
	}

	// Compositor and the binaries the shell can't run without.
	comp, compBin := "generic (experimental)", ""
	switch {
	case os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "":
		comp, compBin = "hyprland", "hyprctl"
	case os.Getenv("NIRI_SOCKET") != "":
		comp, compBin = "niri", "niri"
	default:
		comp, compBin = experimentalBackend()
	}
	add("info", "compositor", "%s", comp)
	for _, b := range []string{"qs", compBin} {
		if b == "" {
			continue
		}
		if have(b) {
			add("ok", "required: "+b, "found")
		} else {
			add("fail", "required: "+b, "not found in PATH")
		}
	}

	// Shell and daemon.
	if res, err := shellCall("compositor", "status"); err == nil {
		var cs struct {
			Backend      string
			Experimental bool
		}
		json.Unmarshal([]byte(res), &cs)
		if cs.Experimental {
			add("ok", "shell", "running, backend %s (experimental: some features may be missing)", cs.Backend)
		} else {
			add("ok", "shell", "running, backend %s", cs.Backend)
		}
	} else {
		add("warn", "shell", "not running (%v)", err)
	}
	sock := ipc.DefaultSocketPath()
	if res, err := ipc.Call(sock, "version", nil); err == nil {
		add("ok", "anod", "running at %s %s", sock, res)
	} else if strings.Contains(err.Error(), ipc.CodeVersion) {
		add("fail", "anod", "%v", err)
	} else {
		add("warn", "anod", "not running (%s): daemon features unavailable", sock)
	}

	// Config.
	eff := map[string]any{}
	if s, err := config.LoadSchema(); err != nil {
		add("fail", "config schema", "%v", err)
	} else if user, err := config.Load(config.UserPath()); err != nil {
		add("fail", "config", "%s: %v", config.UserPath(), err)
	} else {
		var errs, unknown []string
		for _, is := range s.Validate(user) {
			if is.Level == "error" {
				errs = append(errs, is.Key+" ("+is.Msg+")")
			} else {
				unknown = append(unknown, is.Key)
			}
		}
		switch {
		case len(errs) > 0:
			add("fail", "config", "%s", strings.Join(errs, "; "))
		case len(unknown) > 0:
			add("warn", "config", "unknown keys: %s (ano config migrate --prune-unknown)", strings.Join(unknown, ", "))
		case !fileExists(config.UserPath()):
			add("ok", "config", "%s not written yet (defaults)", config.UserPath())
		default:
			add("ok", "config", "%s valid", config.UserPath())
		}
		if bundled, err := config.Load(config.BundledPath()); err == nil {
			eff = config.Merge(bundled, user)
		} else {
			eff = user
		}
	}

	// Optional dependencies of enabled features.
	for _, f := range features {
		if f.When != "" && !anyBool(eff, f.When) {
			continue
		}
		var missing []string
		for _, b := range f.Bins {
			if !have(b) {
				missing = append(missing, b)
			}
		}
		if len(missing) > 0 {
			add("warn", "optional: "+f.Name, "missing %s", strings.Join(missing, ", "))
		}
	}

	// Text recognition: the language data screenshot.ocrLanguages names.
	if have("tesseract") {
		if missing := missingOcrLanguages(eff); len(missing) > 0 {
			add("warn", "optional: text recognition", "no tesseract data for %s (install tesseract-data-%s)", strings.Join(missing, ", "), strings.Join(missing, ", tesseract-data-"))
		}
	}

	// Palette cursor/icon themes: drawn only once one is chosen.
	if strings.HasPrefix(config.String(eff, "cursor.theme", ""), "anoshell-") || strings.HasPrefix(config.String(eff, "icons.theme", ""), "anoshell-") {
		var missing []string
		for _, b := range []string{"rsvg-convert", "magick"} {
			if !have(b) {
				missing = append(missing, b)
			}
		}
		if len(missing) > 0 {
			add("warn", "palette cursors/icons", "missing %s (librsvg, imagemagick)", strings.Join(missing, ", "))
		}
	}

	// Reader: its backend lives in anod; a source on the Python fallback needs the interpreter.
	if config.Bool(eff, "reader.enable", false) {
		if res, err := ipc.Call(sock, "reader.status", nil); err == nil {
			var st struct {
				Error string `json:"error"`
			}
			json.Unmarshal(res, &st)
			if st.Error != "" {
				add("warn", "reader", "%s", st.Error)
			} else {
				add("ok", "reader", "backend available (starts when a panel opens)")
			}
		} else {
			add("warn", "reader", "needs anod, which is not running")
		}
		for _, id := range []string{"freewebnovel", "weebcentral", "allanime"} {
			if config.String(eff, "reader.providers."+id+".backend", "go") != "python" {
				continue
			}
			if py := config.String(eff, "reader.python", "python3"); !have(py) {
				add("warn", "reader: "+id, "set to the Python backend, but %s is not found", py)
			}
		}
	}

	// Last crash.
	if p := supervisor.QuickshellCrashReport(time.Time{}); p != "" {
		fi, _ := os.Stat(p)
		age := time.Since(fi.ModTime()).Round(time.Minute)
		level := "info"
		if age < 24*time.Hour {
			level = "warn"
		}
		add(level, "last crash", "%s (%s ago)", p, age)
	} else {
		add("ok", "last crash", "none recorded")
	}

	// The clock shows the system time: an unsynchronised clock drifts.
	if have("timedatectl") {
		if o, err := exec.Command("timedatectl", "show", "-p", "NTPSynchronized", "--value").Output(); err == nil {
			if strings.TrimSpace(string(o)) == "yes" {
				add("ok", "system clock", "synchronised")
			} else {
				add("warn", "system clock", "not synchronised, so the clock can drift — `sudo timedatectl set-ntp true` turns on systemd-timesyncd")
			}
		}
	}

	// Competing wallpaper rotators.
	if found := runningMatching(rotators); len(found) > 0 {
		// anod applies and rotates wallpapers now: another rotator changes the
		// wallpaper behind its back (and can run twice).
		copies := len(rotatorPIDs())
		add("warn", "wallpaper rotator", "also running: %s (%d process(es)) — run `ano wallpaper migrate` to hand rotation to anod", strings.Join(found, ", "), copies)
	}
	return out
}

// runningMatching returns the rotator names that appear in a running command line.
func runningMatching(names []string) []string {
	seen := map[string]bool{}
	dirs, _ := filepath.Glob("/proc/[0-9]*/cmdline")
	self := fmt.Sprintf("/proc/%d/cmdline", os.Getpid())
	for _, p := range dirs {
		if p == self {
			continue
		}
		b, err := os.ReadFile(p)
		if err != nil || len(b) == 0 {
			continue
		}
		cl := strings.ReplaceAll(string(b), "\x00", " ")
		for _, n := range names {
			if strings.Contains(cl, n) {
				seen[n] = true
			}
		}
	}
	found := make([]string, 0, len(seen))
	for n := range seen {
		found = append(found, n)
	}
	sort.Strings(found)
	return found
}

func sortStrings(s []string) { sort.Strings(s) }

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }

var ocrLang = regexp.MustCompile(`^[A-Za-z_]+$`)

// missingOcrLanguages lists the screenshot.ocrLanguages (default eng) that
// `tesseract --list-langs` doesn't have.
func missingOcrLanguages(eff map[string]any) []string {
	want := []string{"eng"}
	if v, ok := config.Get(eff, "screenshot.ocrLanguages"); ok {
		if l, ok := v.([]any); ok && len(l) > 0 {
			want = want[:0]
			for _, x := range l {
				// The shell's own filter (Screenshot.qml): other entries are dropped.
				if s, ok := x.(string); ok && ocrLang.MatchString(s) {
					want = append(want, s)
				}
			}
		}
	}
	if len(want) == 0 {
		want = []string{"eng"} // what the shell falls back to
	}
	o, err := exec.Command("tesseract", "--list-langs").Output()
	if err != nil {
		return nil
	}
	installed := map[string]bool{}
	for i, line := range strings.Split(string(o), "\n") {
		if i > 0 { // the first line is a heading
			installed[strings.TrimSpace(line)] = true
		}
	}
	var missing []string
	for _, l := range want {
		if !installed[l] {
			missing = append(missing, l)
		}
	}
	return missing
}
