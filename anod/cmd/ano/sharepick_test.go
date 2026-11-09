package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Lists as xdph v1.5.0 builds them (ScreencopyShared.cpp).
const (
	testWindows = "12[HC>]firefox[HT>]Mozilla Firefox[HE>]94251836403712[HA>]" +
		"7[HC>]kitty[HT>]~ $ ls[HE>]0[HA>]" +
		"bad[HC>]x[HT>]y[HE>]1[HA>]"
	testOutputs = "4:DP-1:0:0:2560:1440;8:HDMI-A-1:2560:0:1920:1080;3:bad:0:0:0:0;"
)

func TestParseShareWindows(t *testing.T) {
	w := parseShareWindows(testWindows)
	if len(w) != 2 {
		t.Fatalf("got %d windows: %+v", len(w), w)
	}
	// xdph blanks quotes, $ and ` and any "]" after ">", so no title holds a delimiter.
	if w[0].ID != 12 || w[0].Class != "firefox" || w[0].Title != "Mozilla Firefox" || w[0].Address != "0x55b8b73a7000" {
		t.Errorf("first: %+v", w[0])
	}
	if w[1].ID != 7 || w[1].Title != "~ $ ls" || w[1].Address != "" {
		t.Errorf("second: %+v", w[1])
	}
	if parseShareWindows("") != nil || len(parseShareWindows("1[HC>]truncated")) != 0 {
		t.Error("empty or truncated list gave windows")
	}
}

func TestParseShareOutputs(t *testing.T) {
	o := parseShareOutputs(testOutputs)
	want := []shareOutput{{"DP-1", 0, 0, 2560, 1440}, {"HDMI-A-1", 2560, 0, 1920, 1080}}
	if len(o) != 2 || o[0] != want[0] || o[1] != want[1] {
		t.Fatalf("got %+v", o)
	}
	// A name holding the delimiters is length-prefixed.
	if o := parseShareOutputs("5:a:b;c:1:2:3:4;"); len(o) != 1 || o[0].Name != "a:b;c" || o[0].H != 4 {
		t.Errorf("odd name: %+v", o)
	}
	if o := parseShareOutputs("99:DP-1:0:0:1:1;"); len(o) != 0 {
		t.Errorf("overlong length accepted: %+v", o)
	}
}

func TestSelectionLine(t *testing.T) {
	req := shareRequest{Windows: parseShareWindows(testWindows), Outputs: parseShareOutputs(testOutputs)}
	cases := []struct {
		choice  string
		restore bool
		want    string
	}{
		{"screen:DP-1", true, "[SELECTION]r/screen:DP-1"},
		{"screen:HDMI-A-1", false, "[SELECTION]/screen:HDMI-A-1"},
		{"window:7", false, "[SELECTION]/window:7"},
		{"region:DP-1@10,20,300,400", true, "[SELECTION]r/region:DP-1@10,20,300,400"},
		{"screen:eDP-9", false, ""},               // not offered
		{"window:99", false, ""},                  // not offered
		{"window:-1", false, ""},                  //
		{"region:DP-1@10,20,0,400", false, ""},    // empty
		{"region:DP-1@-1,20,5,5", false, ""},      // negative
		{"region:DP-1@1,2,3", false, ""},          // short
		{"screen:DP-1\n[SELECTION]/x", false, ""}, // a second line
		{"workspace:1", false, ""},
		{"", false, ""},
	}
	for _, c := range cases {
		got, err := selectionLine(req, c.choice, c.restore)
		if got != c.want || (c.want == "") != (err != nil) {
			t.Errorf("%q: got %q, %v; want %q", c.choice, got, err, c.want)
		}
	}
	// No output list (an older portal): any plain name goes through.
	if got, _ := selectionLine(shareRequest{}, "screen:DP-3", false); got != "[SELECTION]/screen:DP-3" {
		t.Errorf("without list: %q", got)
	}
}

func TestSetPicker(t *testing.T) {
	p := "/home/u/.config/quickshell/ano/scripts/share-picker"
	cases := []struct{ in, want string }{
		{"", "screencopy {\n    custom_picker_binary = " + p + "\n}\n"},
		{"screencopy {\n    max_fps = 60\n}\n", "screencopy {\n    custom_picker_binary = " + p + "\n    max_fps = 60\n}\n"},
		{"screencopy {\n  custom_picker_binary = /old # mine\n}\n", "screencopy {\n  custom_picker_binary = " + p + "\n}\n"},
		{"screencopy:custom_picker_binary=/old", "screencopy:custom_picker_binary= " + p},
		{"# screencopy {\n# custom_picker_binary = /x\n", "# screencopy {\n# custom_picker_binary = /x\n\nscreencopy {\n    custom_picker_binary = " + p + "\n}\n"},
	}
	for _, c := range cases {
		if got := setPicker(c.in, p); got != c.want {
			t.Errorf("setPicker(%q) =\n%q\nwant\n%q", c.in, got, c.want)
		}
		if got := currentPicker(setPicker(c.in, p)); got != p {
			t.Errorf("currentPicker after set(%q) = %q", c.in, got)
		}
	}
	if got := currentPicker("screencopy {\n  custom_picker_binary = /old # mine\n}"); got != "/old" {
		t.Errorf("comment kept: %q", got)
	}
}

func TestSharePickInstall(t *testing.T) {
	home := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", home)
	picker := filepath.Join(home, "share-picker")
	os.WriteFile(picker, []byte("#!/bin/sh\n"), 0o755)
	conf := filepath.Join(home, "hypr", "xdph.conf")
	os.MkdirAll(filepath.Dir(conf), 0o755)
	os.WriteFile(conf, []byte("screencopy {\n    max_fps = 60\n}\n"), 0o644)

	if st, _ := xdphPickerStatus(conf, picker); st != "stock" {
		t.Errorf("before: %s", st)
	}
	if rc := sharePickInstall([]string{"--picker", picker}); rc != 0 {
		t.Fatalf("install: %d", rc)
	}
	if st, cur := xdphPickerStatus(conf, picker); st != "ano" || cur != picker {
		t.Errorf("after: %s %s", st, cur)
	}
	baks, _ := filepath.Glob(conf + ".bak-*")
	if len(baks) != 1 {
		t.Fatalf("backups: %v", baks)
	}
	if b, _ := os.ReadFile(baks[0]); string(b) != "screencopy {\n    max_fps = 60\n}\n" {
		t.Errorf("backup holds %q", b)
	}
	if rc := sharePickInstall([]string{"--picker", "relative/path"}); rc == 0 {
		t.Error("relative picker accepted")
	}
}

// The flow against a fake shell: answered, cancelled, and gone (→ fallback).
func TestSharePickFlow(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	t.Setenv("XDPH_WINDOW_SHARING_LIST", testWindows)
	t.Setenv("XDPH_OUTPUT_SHARING_LIST", testOutputs)
	sharePickPoll, sharePickAlive, sharePickTimeout = time.Millisecond, 20*time.Millisecond, 2*time.Second
	defer func() { sharePickShell = shellCall }()

	answer := func(reply string) func(...string) (string, error) {
		return func(args ...string) (string, error) {
			switch args[1] {
			case "pick":
				var req shareRequest
				if err := json.Unmarshal([]byte(args[2]), &req); err != nil || !req.AllowToken || len(req.Windows) != 2 {
					t.Errorf("request: %v %+v", err, req)
				}
				if reply != "" {
					os.WriteFile(req.Reply, []byte(reply), 0o600)
				}
				return "ok", nil
			case "pending":
				return "no", nil // the shell went away (no reply written)
			}
			return "", nil
		}
	}
	sharePickShell = answer(`{"choice":"window:12","restore":true}`)
	if line, err := sharePick([]string{"--allow-token"}); err != nil || line != "[SELECTION]r/window:12" {
		t.Errorf("answered: %q %v", line, err)
	}
	sharePickShell = answer(`{"choice":""}`)
	if line, err := sharePick([]string{"--allow-token"}); err != nil || line != "" {
		t.Errorf("cancelled: %q %v", line, err)
	}
	sharePickShell = answer("")
	if _, err := sharePick([]string{"--allow-token"}); !errors.Is(err, errShellGone) {
		t.Errorf("gone mid-pick: %v", err)
	}
	sharePickShell = func(...string) (string, error) { return "", errors.New("shell not reachable") }
	if _, err := sharePick(nil); err == nil || !strings.Contains(err.Error(), "isn't showing") {
		t.Errorf("unreachable: %v", err)
	}
	// The runtime folder is cleaned up.
	if left, _ := filepath.Glob(filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "ano-share-*")); len(left) != 0 {
		t.Errorf("left behind: %v", left)
	}
}
