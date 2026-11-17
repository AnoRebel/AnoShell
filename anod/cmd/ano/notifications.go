package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/ipc"
	"ano/anod/internal/notifhistory"
)

const notificationsUsage = `usage: ano notifications history [--search TEXT] [--app APP] [--urgency low|normal|critical]
                                  [--since today|7d|30d|DURATION] [--limit N] [--json]
       ano notifications history clear [--search TEXT] [--app APP] [--urgency U] [--since S] | --all  [--yes]
       ano notifications history stats [--json]

The notification history (notifications.history.* in config.json), newest first. Through anod when it runs, else
from the files directly.
`

func notificationsCmd(args []string) int {
	if len(args) == 0 || args[0] != "history" {
		fmt.Fprint(os.Stderr, notificationsUsage)
		return 2
	}
	args = args[1:]
	sub := "list"
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		sub, args = args[0], args[1:]
	}
	fs := flag.NewFlagSet("notifications history "+sub, flag.ContinueOnError)
	search := fs.String("search", "", "text in the summary, body or app name")
	app := fs.String("app", "", "app name")
	urgency := fs.String("urgency", "", "low, normal or critical (comma-separated)")
	since := fs.String("since", "", "today, 7d, 30d or a duration such as 12h")
	limit := fs.Int("limit", 20, "entries to print")
	asJSON := fs.Bool("json", false, "JSON output")
	all := fs.Bool("all", false, "clear: everything")
	yes := fs.Bool("yes", false, "clear: don't ask")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	q := notifhistory.Query{Text: *search, App: *app, Limit: *limit}
	for u := range strings.SplitSeq(*urgency, ",") {
		if u = strings.TrimSpace(u); u != "" {
			q.Urgency = append(q.Urgency, u)
		}
	}
	if *since != "" {
		t, err := parseSince(*since, time.Now())
		if err != nil {
			fmt.Fprintln(os.Stderr, "ano notifications:", err)
			return 2
		}
		q.Since = t.UnixMilli()
	}
	h := openHistory()
	fail := func(err error) int { fmt.Fprintln(os.Stderr, "ano notifications:", err); return 1 }

	switch sub {
	case "list":
		p, err := h.query(q)
		if err != nil {
			return fail(err)
		}
		if *asJSON {
			json.NewEncoder(os.Stdout).Encode(p)
			return 0
		}
		printEntries(os.Stdout, p)
		return 0
	case "stats":
		st, err := h.stats()
		if err != nil {
			return fail(err)
		}
		if *asJSON {
			json.NewEncoder(os.Stdout).Encode(st)
			return 0
		}
		state := "on"
		if !st.Enable {
			state = "off"
		}
		fmt.Printf("history %s · %d entries · %d files, %.1f MB · %s\n", state, st.Count, st.Files, float64(st.Bytes)/(1<<20), st.Dir)
		if st.Error != "" {
			fmt.Println("problem:", st.Error)
		}
		return 0
	case "clear":
		filtered := q.Text != "" || q.App != "" || len(q.Urgency) > 0 || q.Since != 0
		if !filtered && !*all {
			fmt.Fprintln(os.Stderr, "ano notifications: say what to clear (--search, --app, --urgency, --since) or --all")
			return 2
		}
		q.Limit = 1
		p, err := h.query(q)
		if err != nil {
			return fail(err)
		}
		if p.Total == 0 {
			fmt.Println("nothing to clear")
			return 0
		}
		if !*yes && !confirm(fmt.Sprintf("Delete %d notification(s) from the history? This can't be undone. [y/N] ", p.Total)) {
			fmt.Println("kept")
			return 1
		}
		q.Limit = 0
		n, err := h.delete(q, !filtered)
		if err != nil {
			return fail(err)
		}
		fmt.Printf("deleted %d\n", n)
		return 0
	}
	fmt.Fprint(os.Stderr, notificationsUsage)
	return 2
}

func parseSince(s string, now time.Time) (time.Time, error) {
	switch s {
	case "today":
		y, m, d := now.Date()
		return time.Date(y, m, d, 0, 0, 0, 0, now.Location()), nil
	case "all":
		return time.Time{}, nil
	}
	if n, ok := strings.CutSuffix(s, "d"); ok {
		if d, err := strconv.Atoi(n); err == nil && d >= 0 {
			return now.AddDate(0, 0, -d), nil
		}
	}
	d, err := time.ParseDuration(s)
	if err != nil || d < 0 {
		return time.Time{}, fmt.Errorf("--since: want today, 7d, 30d or a duration such as 12h, not %q", s)
	}
	return now.Add(-d), nil
}

func printEntries(w io.Writer, p notifhistory.Page) {
	if len(p.Entries) == 0 {
		fmt.Fprintln(w, "no notifications match")
		return
	}
	for _, e := range p.Entries {
		body, _, _ := strings.Cut(strings.TrimSpace(e.Body), "\n")
		line := e.Summary
		if body != "" {
			line += " — " + body
		}
		mark := ""
		if e.Urgency == "critical" {
			mark = " !"
		}
		fmt.Fprintf(w, "%s  %-16s %s%s\n", time.UnixMilli(e.Time).Format("2006-01-02 15:04"), clip(e.App, 16), clip(line, 100), mark)
	}
	if p.Total > len(p.Entries) {
		fmt.Fprintf(w, "… %d of %d shown (--limit)\n", len(p.Entries), p.Total)
	}
}

func clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

// history talks to anod when it runs (so writes don't race its appends), else to the files.
type history struct {
	sock  string
	local *notifhistory.Store
}

func openHistory() history {
	home, _ := os.UserHomeDir()
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		data = filepath.Join(home, ".local", "share")
	}
	local := &notifhistory.Store{Settings: func() notifhistory.Settings {
		m, err := config.Effective()
		if err != nil {
			m = map[string]any{}
		}
		return notifhistory.FromConfig(m, data, home)
	}}
	return history{sock: ipc.DefaultSocketPath(), local: local}
}

func (h history) call(method string, params, out any) (bool, error) {
	raw, err := ipc.Call(h.sock, method, params)
	if errors.Is(err, ipc.ErrNotRunning) {
		return false, nil
	}
	if err != nil {
		return true, err
	}
	return true, json.Unmarshal(raw, out)
}

func (h history) query(q notifhistory.Query) (notifhistory.Page, error) {
	var p notifhistory.Page
	if ok, err := h.call("notifhistory.query", q, &p); ok {
		return p, err
	}
	return h.local.Query(q), nil
}

func (h history) stats() (notifhistory.Stats, error) {
	var st notifhistory.Stats
	if ok, err := h.call("notifhistory.stats", nil, &st); ok {
		return st, err
	}
	return h.local.Stats(), nil
}

func (h history) delete(q notifhistory.Query, all bool) (int, error) {
	var r struct {
		Deleted int `json:"deleted"`
	}
	req := struct {
		notifhistory.Query
		All bool `json:"all"`
	}{q, all}
	if ok, err := h.call("notifhistory.delete", req, &r); ok {
		return r.Deleted, err
	}
	return h.local.Delete(q, all)
}
