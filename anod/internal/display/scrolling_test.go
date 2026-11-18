package display

import (
	"os"
	"strings"
	"testing"
)

func TestCleanScrolling(t *testing.T) {
	s := CleanScrolling(Scrolling{
		ColumnWidth: 1.5,
		Workspaces:  []ScrollWorkspace{{ID: 3}, {ID: 3, Direction: "left"}, {ID: 4, Direction: "sideways"}, {ID: 0}, {ID: 5, Direction: "down"}},
		Apps:        []ScrollApp{{App: "firefox", Width: 0.8}, {App: `x"); os.exit() --`, Width: 0.5}, {App: "kitty", Width: 2}, {App: "firefox", Width: 0.3}},
	})
	if s.ColumnWidth != 0 {
		t.Errorf("width outside 0.1–1 kept: %v", s.ColumnWidth)
	}
	if len(s.Workspaces) != 2 || s.Workspaces[0] != (ScrollWorkspace{3, "right"}) || s.Workspaces[1] != (ScrollWorkspace{5, "down"}) {
		t.Errorf("workspaces: %+v", s.Workspaces)
	}
	if len(s.Apps) != 1 || s.Apps[0].App != "firefox" || s.Apps[0].Width != 0.8 {
		t.Errorf("apps: %+v", s.Apps)
	}
}

var sample = &Scrolling{ColumnWidth: 0.5, Workspaces: []ScrollWorkspace{{3, "right"}, {5, "down"}},
	Apps: []ScrollApp{{"org.mozilla.firefox", 0.8}}}

func TestHyprScrolling(t *testing.T) {
	got := hyprScrolling(sample)
	for _, want := range []string{
		`hl.config({ scrolling = { column_width = 0.5 } })`,
		`hl.workspace_rule({ workspace = "3", layout = "scrolling", layout_opts = { direction = "right" } })`,
		`hl.workspace_rule({ workspace = "5", layout = "scrolling", layout_opts = { direction = "down" } })`,
		`hl.window_rule({ name = "ano-scroll-org.mozilla.firefox", match = { class = "^org\\.mozilla\\.firefox$" }, scrolling_width = 0.8 })`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %s in\n%s", want, got)
		}
	}
	if hyprScrolling(nil) != "" {
		t.Error("nil writes something")
	}
}

func TestHyprScrollingUndo(t *testing.T) {
	cur := &Scrolling{Workspaces: []ScrollWorkspace{{3, "right"}}}
	got := hyprScrollingUndo(sample, cur, "master")
	if strings.Contains(got, `workspace = "3"`) || !strings.Contains(got, `hl.workspace_rule({ workspace = "5", layout = "master" })`) {
		t.Errorf("workspace undo:\n%s", got)
	}
	if !strings.Contains(got, `name = "ano-scroll-org.mozilla.firefox"`) || !strings.Contains(got, `:set_enabled(false)`) {
		t.Errorf("app undo:\n%s", got)
	}
	if hyprScrollingUndo(nil, cur, "") != "" || hyprScrollingUndo(sample, sample, "") != "" {
		t.Error("undo with nothing removed")
	}
}

func TestNiriScrolling(t *testing.T) {
	got := niriScrolling(sample)
	for _, want := range []string{"default-column-width { proportion 0.5; }", `match app-id=r#"^org\.mozilla\.firefox$"#`, "proportion 0.8;"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %s in\n%s", want, got)
		}
	}
	if strings.Contains(got, "workspace") {
		t.Error("niri has no per-workspace layout")
	}
}

func TestMangoScrolling(t *testing.T) {
	got := MangoScrolling(sample)
	for _, want := range []string{"scroller_default_proportion=0.5\n", "tag_rule=id:3,layout_name:scroller\n",
		"tag_rule=id:5,layout_name:vertical_scroller\n", `window_rule=scroller_proportion:0.8,app_id:^org\.mozilla\.firefox$` + "\n"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in\n%s", want, got)
		}
	}
}

// The managed file carries the scrolling block, and RefreshScrolling evals the
// change on Hyprland: undo of what was dropped, then the current rules.
func TestRefreshScrollingHyprland(t *testing.T) {
	f := &fake{outs: []Output{edp}}
	s, dir := newSvc(t, f)
	cur := sample
	s.Scrolling = func() *Scrolling { return cur }
	var evals []string
	s.Exec = func(name string, args ...string) error {
		if name == "hyprctl" && len(args) == 2 && args[0] == "eval" {
			evals = append(evals, args[1])
		}
		return nil
	}
	if err := s.RefreshScrolling(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(dir + "/hypr/ano-managed.lua")
	if !strings.Contains(string(b), `layout = "scrolling"`) {
		t.Errorf("managed file:\n%s", b)
	}
	cur = &Scrolling{Workspaces: []ScrollWorkspace{{3, "right"}}}
	if err := s.RefreshScrolling(); err != nil {
		t.Fatal(err)
	}
	if len(evals) != 2 || !strings.Contains(evals[1], `workspace = "5", layout = "dwindle"`) || !strings.Contains(evals[1], "set_enabled(false)") {
		t.Errorf("evals: %q", evals)
	}
}
