package main

// The install and uninstall wizards (Bubble Tea v2, styled like the setup
// menu): they only ask the questions, then run the embedded installer script
// (anod/installer) with the answers as flags, in the foreground, so sudo and
// the script's own output have the terminal. The scripts are the canonical
// implementation; everything here can be done with their flags directly.

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"

	"ano/anod/installer"
)

// compositors the installer has bundled configs for, with the command that
// shows one is installed.
var wizardCompositors = []struct{ name, cmd string }{
	{"hyprland", "Hyprland"}, {"niri", "niri"}, {"sway", "sway"},
	{"mango", "mango"}, {"labwc", "labwc"}, {"umbriel", "umbriel"},
}

// missingDeps reads install.sh's dependency table (command → packages) and
// returns the commands this system lacks.
func missingDeps() []string {
	row := regexp.MustCompile(`^\s+"(\S+)\s+\S+`)
	var out []string
	in := false
	for l := range strings.SplitSeq(string(installer.Install), "\n") {
		switch {
		case strings.HasPrefix(l, "deps_table=("):
			in = true
		case in && strings.TrimSpace(l) == ")":
			in = false
		case in:
			if m := row.FindStringSubmatch(l); m != nil {
				if _, err := exec.LookPath(m[1]); err != nil {
					out = append(out, m[1])
				}
			}
		}
	}
	return out
}

type wizOption struct {
	label, hint, value string // value: the compositor name (install)
	on                 bool
}

type wizard struct {
	kind      string // install | uninstall
	channel   string
	version   string
	st        styles
	opts      []wizOption // toggles on the first screen
	comps     []int       // indexes into opts that are compositors (install)
	cur       int
	confirm   bool // on the summary screen
	run       bool // chosen: run the script
	cancelled bool
}

func newWizard(kind, channel, version string) *wizard {
	w := &wizard{kind: kind, channel: channel, version: version, st: newStyles(newPalette(true))}
	if kind == "install" {
		miss := missingDeps()
		hint := "all required programs are installed"
		if len(miss) > 0 {
			hint = "missing: " + strings.Join(miss, ", ") + " (asks sudo; your repos only, no third-party ones)"
		}
		w.opts = append(w.opts, wizOption{label: "Install missing dependencies", hint: hint, on: len(miss) > 0})
		for _, c := range wizardCompositors {
			if _, err := exec.LookPath(c.cmd); err != nil {
				continue
			}
			w.comps = append(w.comps, len(w.opts))
			w.opts = append(w.opts, wizOption{label: "Use the bundled " + c.name + " config", hint: "yours is moved aside and restored by the uninstaller", value: c.name})
		}
	} else {
		w.opts = append(w.opts, wizOption{label: "Also remove my settings and history",
			hint: "~/.config/anoshell, ~/.local/state/anoshell, ~/.local/share/anoshell (off: kept for a reinstall)"})
	}
	return w
}

func (w *wizard) Init() tea.Cmd { return tea.RequestBackgroundColor }

func (w *wizard) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.BackgroundColorMsg:
		w.st = newStyles(newPalette(msg.IsDark()))
	case tea.KeyPressMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			w.cancelled = true
			return w, tea.Quit
		case "esc":
			if w.confirm {
				w.confirm = false
				return w, nil
			}
			w.cancelled = true
			return w, tea.Quit
		case "up", "k":
			if !w.confirm && w.cur > 0 {
				w.cur--
			}
		case "down", "j":
			if !w.confirm && w.cur < len(w.opts)-1 {
				w.cur++
			}
		case "space", " ", "x":
			if !w.confirm {
				w.opts[w.cur].on = !w.opts[w.cur].on
			}
		case "enter":
			if w.confirm {
				w.run = true
				return w, tea.Quit
			}
			w.confirm = true
		}
	}
	return w, nil
}

// flags turns the answers into the script's flags.
func (w *wizard) flags() []string {
	var f []string
	if w.kind == "install" {
		f = append(f, "--channel", w.channel)
		if w.version != "" {
			f = append(f, "--version", w.version)
		}
		if w.opts[0].on {
			f = append(f, "--yes")
		} else {
			f = append(f, "--no-deps")
		}
		any := false
		for _, i := range w.comps {
			if w.opts[i].on {
				f = append(f, "--compositor", w.opts[i].value)
				any = true
			}
		}
		if !any {
			f = append(f, "--no-compositor")
		}
		return f
	}
	f = append(f, "--yes")
	if w.opts[0].on {
		f = append(f, "--purge")
	}
	return f
}

func (w *wizard) View() tea.View {
	title := "Install AnoShell"
	target := w.channel + " channel"
	if w.version != "" {
		target = w.version
	}
	if w.kind == "uninstall" {
		title, target = "Uninstall AnoShell", "removes the program; changes to your files are undone"
	}
	var b strings.Builder
	if !w.confirm {
		for i, o := range w.opts {
			box := "[ ]"
			if o.on {
				box = w.st.success.Render("[x]")
			}
			line := fmt.Sprintf("%s %s", box, o.label)
			if i == w.cur {
				line = w.st.cursor.Render("› ") + line
			} else {
				line = "  " + line
			}
			b.WriteString(line + "\n    " + w.st.muted.Render(o.hint) + "\n")
		}
		if w.kind == "install" && len(w.comps) == 0 {
			b.WriteString("\n" + w.st.muted.Render("No supported compositor found: add `ano start` to yours (docs: Installation).") + "\n")
		}
	} else {
		b.WriteString(w.st.header.Render("This runs:") + "\n")
		script := "install.sh"
		if w.kind == "uninstall" {
			script = "uninstall.sh"
		}
		b.WriteString("  " + script + " " + strings.Join(w.flags(), " ") + "\n\n")
		if w.kind == "install" {
			b.WriteString(w.st.muted.Render("Clones the shell to ~/.config/quickshell/ano, installs anod + ano to ~/.local/bin, runs ano doctor.") + "\n")
		} else {
			b.WriteString(w.st.danger.Render("The shell, anod/ano and AnoShell's generated themes are removed.") + "\n")
		}
	}
	help := "↑/↓ move · space toggles · enter next · esc cancel"
	if w.confirm {
		help = "enter runs it · esc goes back · q quits"
	}
	v := tea.NewView(lipgloss.JoinVertical(lipgloss.Left,
		w.st.title.Render(title+" · "+target),
		"",
		w.st.panel.Render(strings.TrimRight(b.String(), "\n")),
		"",
		w.st.helpBar.Render(help),
	))
	v.WindowTitle = title
	return v
}

// runInstallerScript runs one of the embedded scripts with args, attached to
// this terminal. ANO_FROM_WIZARD stops install.sh from opening the wizard again.
func runInstallerScript(name string, args []string) int {
	script := installer.Install
	if name == "uninstall" {
		script = installer.Uninstall
	}
	f, err := os.CreateTemp("", "anoshell-"+name+"-*.sh")
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano setup:", err)
		return 1
	}
	defer os.Remove(f.Name())
	if _, err := f.Write(script); err != nil {
		f.Close()
		fmt.Fprintln(os.Stderr, "ano setup:", err)
		return 1
	}
	f.Close()
	c := exec.Command("bash", append([]string{f.Name()}, args...)...)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	c.Env = append(os.Environ(), "ANO_FROM_WIZARD=1")
	if err := c.Run(); err != nil {
		if ee, ok := errors.AsType[*exec.ExitError](err); ok {
			return ee.ExitCode()
		}
		fmt.Fprintln(os.Stderr, "ano setup:", err)
		return 1
	}
	return 0
}

// setupWizard asks, then runs. 130: cancelled.
func setupWizard(kind, channel, version string) int {
	w := newWizard(kind, channel, version)
	if _, err := tea.NewProgram(w).Run(); err != nil {
		fmt.Fprintln(os.Stderr, "ano setup:", err)
		return 1
	}
	if !w.run {
		fmt.Println("cancelled: nothing was changed")
		return 130
	}
	return runInstallerScript(kind, w.flags())
}
