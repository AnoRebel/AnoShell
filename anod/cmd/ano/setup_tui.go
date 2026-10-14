package main

// Interactive front end for `ano setup` (Bubble Tea v2, styled like
// btrfs-migrate). It is a convenience layer: every action runs the same
// `ano setup <action>` subcommand, which also works without it.

import (
	"fmt"
	"image/color"
	"io"
	"os"
	"os/exec"
	"strings"

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
	{"Refresh", "rebuild, migrate the config, restart (no pull)", []string{"setup", "refresh"}, true},
	{"Install", "clone the shell if missing, build, run doctor", []string{"setup", "install"}, true},
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

type ranMsg struct {
	out    string
	err    error
	dryRun bool
}

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
	return m
}

// run executes `ano <args>` with captured output. The binary re-invokes
// itself so the TUI and the plain commands share one implementation.
func run(args []string, dryRun bool) tea.Cmd {
	return func() tea.Msg {
		self, err := os.Executable()
		if err != nil {
			return ranMsg{err: err}
		}
		out, err := exec.Command(self, args...).CombinedOutput()
		return ranMsg{out: string(out), err: err, dryRun: dryRun}
	}
}

func (m *tui) Init() tea.Cmd { return nil }

func (m *tui) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.BackgroundColorMsg:
		m.st = newStyles(newPalette(msg.IsDark()))
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		m.out.SetWidth(max(20, msg.Width-6))
		m.out.SetHeight(max(5, msg.Height-12))
		m.help.SetWidth(msg.Width)
	case ranMsg:
		m.lastErr = msg.err
		m.out.SetContent(strings.TrimRight(msg.out, "\n"))
		m.out.GotoTop()
		if msg.dryRun {
			m.scr = scrReview
		} else {
			m.scr = scrResult
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
				m.scr = scrRunning
				args := m.cur.args
				if m.cur.changes {
					args = append(append([]string{}, args...), "--dry-run")
				}
				return m, tea.Batch(m.spin.Tick, run(args, m.cur.changes))
			case scrReview:
				m.scr = scrRunning
				return m, tea.Batch(m.spin.Tick, run(m.cur.args, false))
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
	case scrReview, scrResult:
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
		header = m.cur.title
		body = m.spin.View() + " running ano " + strings.Join(m.cur.args, " ") + " …"
	case scrResult:
		header = m.cur.title
		body = m.st.panel.Render(m.out.View())
		if m.lastErr != nil {
			footer = m.st.danger.Render("✘ " + m.lastErr.Error())
		} else {
			footer = m.st.success.Render("✓ done")
		}
		footer += m.st.muted.Render("  · enter/esc back to the menu")
	}
	v := tea.NewView(lipgloss.JoinVertical(lipgloss.Left,
		m.st.title.Render("ano setup "+versionString()),
		"",
		m.st.header.Render(header),
		"",
		body,
		"",
		footer,
		m.st.helpBar.Render(m.help.View(keys)),
	))
	v.AltScreen = true
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
