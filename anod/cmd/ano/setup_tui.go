package main

// Interactive AnoShell setup: the front end for `ano setup` (Bubble Tea v2, styled like
// btrfs-migrate). It is a convenience layer: every action runs the same
// `ano setup <action>` subcommand, which also works without it.

import (
	"bufio"
	"fmt"
	"image/color"
	"io"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"charm.land/bubbles/v2/help"
	"charm.land/bubbles/v2/key"
	"charm.land/bubbles/v2/list"
	"charm.land/bubbles/v2/spinner"
	"charm.land/bubbles/v2/viewport"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

type palette struct{ brand, accent, success, danger, muted, border, fg, titleBG, titleFG color.Color }

func newPalette(isDark bool) palette {
	pick := lipgloss.LightDark(isDark)
	return palette{
		brand:   pick(lipgloss.Color("#7D56F4"), lipgloss.Color("#BD93F9")),
		accent:  pick(lipgloss.Color("#FF6AC1"), lipgloss.Color("#FF79C6")),
		success: pick(lipgloss.Color("#02BA84"), lipgloss.Color("#50FA7B")),
		danger:  pick(lipgloss.Color("#D7263D"), lipgloss.Color("#FF5555")),
		muted:   pick(lipgloss.Color("#6C6F85"), lipgloss.Color("#7B7F9E")),
		border:  pick(lipgloss.Color("#B0B4C8"), lipgloss.Color("#44475A")),
		fg:      pick(lipgloss.Color("#282A36"), lipgloss.Color("#F8F8F2")),
		titleBG: pick(lipgloss.Color("#7D56F4"), lipgloss.Color("#BD93F9")),
		titleFG: pick(lipgloss.Color("#FFFFFF"), lipgloss.Color("#1E1F29")),
	}
}

type styles struct{ title, header, muted, keyVal, cursor, success, danger, panel, helpBar lipgloss.Style }

func newStyles(p palette) styles {
	return styles{
		title:   lipgloss.NewStyle().Bold(true).Foreground(p.titleFG).Background(p.titleBG).Padding(0, 2),
		header:  lipgloss.NewStyle().Bold(true).Foreground(p.accent),
		muted:   lipgloss.NewStyle().Foreground(p.muted),
		keyVal:  lipgloss.NewStyle().Foreground(p.fg),
		cursor:  lipgloss.NewStyle().Foreground(p.accent).Bold(true),
		success: lipgloss.NewStyle().Foreground(p.success).Bold(true),
		danger:  lipgloss.NewStyle().Foreground(p.danger).Bold(true),
		panel:   lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(p.border).Padding(0, 1),
		helpBar: lipgloss.NewStyle().Foreground(p.muted),
	}
}

// action is one menu entry. Changing actions get a review screen showing
// their --dry-run plan first; read-only ones run straight away.
type action struct {
	title, desc string
	args        []string
	changes     bool
}

func (a action) FilterValue() string { return a.title }

var actions = []action{
	{"Status", "checkout, remote, versions and config", []string{"setup", "status", "--fetch"}, false},
	{"Update", "fast-forward from the remote, rebuild, migrate, restart", []string{"setup", "update"}, true},
	{"Force update", "stash local changes, keep local commits on a backup branch, reset to the remote", []string{"setup", "update", "--force"}, true},
	{"Refresh", "rebuild, migrate the config, restart (no pull)", []string{"setup", "refresh"}, true},
	{"Install", "clone the shell if missing, build, run doctor", []string{"setup", "install"}, true},
	{"Back up", "archive your config, themes, widgets and data (ano backup create)", []string{"backup", "create"}, false},
	{"Doctor", "check dependencies, config, sockets and crashes", []string{"doctor"}, false},
}

type delegate struct{ st *styles }

func (d delegate) Height() int                             { return 2 }
func (d delegate) Spacing() int                            { return 1 }
func (d delegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd { return nil }
func (d delegate) Render(w io.Writer, m list.Model, index int, it list.Item) {
	a := it.(action)
	cursor, title, desc := "  ", d.st.keyVal, d.st.muted
	if index == m.Index() {
		cursor, title = d.st.cursor.Render("❯ "), d.st.cursor
	}
	fmt.Fprintf(w, "%s%s\n    %s", cursor, title.Render(a.title), desc.Render(a.desc))
}

type keymap struct{ Up, Down, Enter, Back, Quit key.Binding }

func (k keymap) ShortHelp() []key.Binding {
	return []key.Binding{k.Up, k.Down, k.Enter, k.Back, k.Quit}
}
func (k keymap) FullHelp() [][]key.Binding { return [][]key.Binding{k.ShortHelp()} }

var keys = keymap{
	Up:    key.NewBinding(key.WithKeys("up", "k"), key.WithHelp("↑/k", "up")),
	Down:  key.NewBinding(key.WithKeys("down", "j"), key.WithHelp("↓/j", "down")),
	Enter: key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "select / run")),
	Back:  key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc", "back")),
	Quit:  key.NewBinding(key.WithKeys("q", "ctrl+c"), key.WithHelp("q", "quit")),
}

type screen int

const (
	scrMenu screen = iota
	scrReview
	scrRunning
	scrResult
)

// lineMsg is one line of live output; ranMsg ends a run (out is set only
// when the whole output arrives at once, as in tests).
type lineMsg string

type ranMsg struct {
	out    string
	err    error
	dryRun bool
}

// job is a running `ano …` child whose output streams into the TUI.
type job struct {
	cmd    *exec.Cmd
	lines  chan string
	done   chan error
	dryRun bool
}

const maxLines = 5000 // live output kept for scrolling

type tui struct {
	scr     screen
	menu    list.Model
	out     viewport.Model
	spin    spinner.Model
	help    help.Model
	st      styles
	cur     action
	lastErr error
	w, h    int

	job       *job
	lines     []string
	started   time.Time
	elapsed   time.Duration
	cancelled bool
}

func newTUI() *tui {
	st := newStyles(newPalette(true))
	items := make([]list.Item, len(actions))
	for i, a := range actions {
		items[i] = a
	}
	m := &tui{st: st, help: help.New(), spin: spinner.New(spinner.WithSpinner(spinner.MiniDot))}
	// Each entry is 2 lines + 1 spacing; one page holds them all.
	m.menu = list.New(items, delegate{st: &m.st}, 70, len(actions)*3)
	m.menu.SetShowPagination(false)
	m.menu.SetShowStatusBar(false)
	m.menu.SetFilteringEnabled(false)
	m.menu.SetShowHelp(false)
	m.menu.SetShowTitle(false)
	m.out = viewport.New(viewport.WithWidth(80), viewport.WithHeight(16))
	m.out.SoftWrap = true // long status/plan lines wrap instead of being cut
	return m
}

// start runs `ano <args>` (the binary re-invokes itself, so the TUI and the
// plain commands share one implementation) in its own process group, with
// stdout and stderr streamed line by line.
func start(args []string, dryRun bool) (*job, error) {
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	pr, pw := io.Pipe()
	c := exec.Command(self, args...)
	c.Stdout, c.Stderr = pw, pw
	c.SysProcAttr = &syscall.SysProcAttr{Setpgid: true} // cancel stops its children too
	if err := c.Start(); err != nil {
		return nil, err
	}
	j := &job{cmd: c, lines: make(chan string, 64), done: make(chan error, 1), dryRun: dryRun}
	go func() {
		sc := bufio.NewScanner(pr)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		for sc.Scan() {
			j.lines <- sc.Text()
		}
		close(j.lines)
	}()
	go func() { err := c.Wait(); pw.Close(); j.done <- err }()
	return j, nil
}

// next waits for the job's next line, or its end once the output is drained.
func (j *job) next() tea.Cmd {
	return func() tea.Msg {
		if l, ok := <-j.lines; ok {
			return lineMsg(l)
		}
		return ranMsg{err: <-j.done, dryRun: j.dryRun}
	}
}

type tickMsg struct{}

func tick() tea.Cmd { return tea.Tick(time.Second, func(time.Time) tea.Msg { return tickMsg{} }) }

func (m *tui) run(args []string, dryRun bool) tea.Cmd {
	m.scr, m.lines, m.cancelled, m.lastErr = scrRunning, nil, false, nil
	m.started, m.elapsed = time.Now(), 0
	m.out.SetContent("")
	j, err := start(args, dryRun)
	if err != nil {
		return func() tea.Msg { return ranMsg{err: err} }
	}
	m.job = j
	return tea.Batch(m.spin.Tick, tick(), j.next())
}

// render colours step headings, commands and failures in the output.
func (m *tui) render() string {
	out := make([]string, len(m.lines))
	for i, l := range m.lines {
		t := strings.TrimSpace(l)
		switch {
		case strings.HasPrefix(t, "→ "):
			out[i] = m.st.header.Render(l)
		case strings.HasPrefix(t, "OK "), strings.HasPrefix(t, "✓"):
			out[i] = m.st.success.Render(l)
		case strings.HasPrefix(t, "WARN"):
			out[i] = m.st.cursor.Render(l)
		case strings.HasPrefix(t, "$ "):
			out[i] = m.st.muted.Render(l)
		case strings.HasPrefix(t, "✘"), strings.Contains(t, "FAIL"), strings.HasPrefix(strings.ToLower(t), "error"), strings.HasPrefix(t, "ano setup:"):
			out[i] = m.st.danger.Render(l)
		default:
			out[i] = l
		}
	}
	return strings.Join(out, "\n")
}

// resize fits the menu and the output panel to the terminal.
func (m *tui) resize() {
	m.menu.SetSize(min(max(30, m.w-2), 100), min(len(actions)*3, max(6, m.h-8)))
	m.out.SetWidth(max(20, m.w-6))
	m.out.SetHeight(max(4, m.h-12))
	m.help.SetWidth(m.w)
}

// The terminal's background picks the light or dark palette (v2 only reports
// it when asked).
func (m *tui) Init() tea.Cmd { return tea.RequestBackgroundColor }

func (m *tui) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.BackgroundColorMsg:
		m.st = newStyles(newPalette(msg.IsDark()))
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		m.resize()
	case lineMsg:
		m.lines = append(m.lines, string(msg))
		if len(m.lines) > maxLines {
			m.lines = m.lines[len(m.lines)-maxLines:]
		}
		m.out.SetContent(m.render())
		m.out.GotoBottom() // follow the live output
		if m.job != nil {
			return m, m.job.next()
		}
		return m, nil
	case tickMsg:
		if m.scr == scrRunning {
			m.elapsed = time.Since(m.started).Round(time.Second)
			return m, tick()
		}
		return m, nil
	case ranMsg:
		m.job, m.lastErr = nil, msg.err
		m.elapsed = time.Since(m.started).Round(100 * time.Millisecond)
		if msg.out != "" {
			m.lines = strings.Split(strings.TrimRight(msg.out, "\n"), "\n")
		}
		m.out.SetContent(m.render())
		if msg.dryRun && msg.err == nil {
			m.scr = scrReview
			m.out.GotoTop()
		} else {
			m.scr = scrResult
			m.out.GotoBottom()
		}
		return m, nil
	case spinner.TickMsg:
		if m.scr == scrRunning {
			var cmd tea.Cmd
			m.spin, cmd = m.spin.Update(msg)
			return m, cmd
		}
	case tea.KeyPressMsg:
		switch {
		case m.scr == scrRunning && msg.String() == "ctrl+c" && m.job != nil:
			// Stop the whole process group; the run ends with its exit status.
			m.cancelled = true
			syscall.Kill(-m.job.cmd.Process.Pid, syscall.SIGINT)
			return m, nil
		case key.Matches(msg, keys.Quit):
			if m.scr != scrRunning {
				return m, tea.Quit
			}
		case key.Matches(msg, keys.Back):
			if m.scr == scrReview || m.scr == scrResult {
				m.scr = scrMenu
			}
			return m, nil
		case key.Matches(msg, keys.Enter):
			switch m.scr {
			case scrMenu:
				m.cur = m.menu.SelectedItem().(action)
				args := m.cur.args
				if m.cur.changes {
					args = append(append([]string{}, args...), "--dry-run")
				}
				return m, m.run(args, m.cur.changes)
			case scrReview:
				return m, m.run(m.cur.args, false)
			case scrResult:
				m.scr = scrMenu
				return m, nil
			}
		}
	}
	var cmd tea.Cmd
	switch m.scr {
	case scrMenu:
		m.menu, cmd = m.menu.Update(msg)
	case scrReview, scrResult, scrRunning:
		m.out, cmd = m.out.Update(msg)
	}
	return m, cmd
}

func (m *tui) View() tea.View {
	var header, body, footer string
	switch m.scr {
	case scrMenu:
		header = "What do you want to do?"
		body = m.menu.View()
	case scrReview:
		header = m.cur.title + ": plan"
		body = m.st.panel.Render(m.out.View())
		footer = m.st.muted.Render("enter runs these steps · esc goes back")
	case scrRunning:
		header = fmt.Sprintf("%s %s · %s", m.spin.View(), m.cur.title, m.elapsed)
		body = m.st.panel.Render(m.out.View())
		if len(m.lines) == 0 {
			body = m.st.panel.Render(m.st.muted.Render("starting ano " + strings.Join(m.cur.args, " ") + " …"))
		}
		footer = m.st.muted.Render("running · ctrl+c cancels")
		if m.cancelled {
			footer = m.st.danger.Render("cancelling …")
		}
	case scrResult:
		header = m.cur.title
		body = m.st.panel.Render(m.out.View())
		switch {
		case m.cancelled:
			footer = m.st.danger.Render("✘ cancelled")
		case m.lastErr != nil:
			footer = m.st.danger.Render("✘ " + m.lastErr.Error())
		default:
			footer = m.st.success.Render("✓ done")
		}
		footer += m.st.muted.Render(fmt.Sprintf(" in %s · enter/esc back to the menu", m.elapsed))
	}
	v := tea.NewView(lipgloss.JoinVertical(lipgloss.Left,
		m.st.title.Render("AnoShell setup · ano "+versionString()),
		"",
		m.st.header.Render(header),
		"",
		body,
		"",
		footer,
		m.st.helpBar.Render(m.help.View(keys)),
	))
	v.AltScreen = true
	v.WindowTitle = "AnoShell setup"
	return v
}

// isTerminal reports whether stdin and stdout are interactive terminals.
func isTerminal() bool {
	for _, f := range []*os.File{os.Stdin, os.Stdout} {
		if fi, err := f.Stat(); err != nil || fi.Mode()&os.ModeCharDevice == 0 {
			return false
		}
	}
	return true
}

func setupTUI() int {
	if _, err := tea.NewProgram(newTUI()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, "ano setup:", err)
		return 1
	}
	return 0
}
