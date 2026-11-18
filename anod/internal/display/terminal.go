package display

// Terminal windows' blur (terminal.blur), written into the managed file: Hyprland blurs
// translucent windows when its own blur is on, so it only needs a rule to stop that;
// niri (26.04+) blurs only windows a rule asks for.

// TerminalLook is what the managed file needs from terminal.*.
type TerminalLook struct {
	Translucent bool // terminal.background isn't "solid"
	Blur        bool // terminal.blur
}

// The supported terminals' classes / app ids (foot's server windows are footclient).
const terminalApps = `^(kitty|foot|footclient|com\.mitchellh\.ghostty|Alacritty)$`

func hyprTerminal(t *TerminalLook) string {
	if t == nil || !t.Translucent || t.Blur {
		return ""
	}
	return "hl.window_rule({ match = { class = \"" + luaEscape(terminalApps) + "\" }, no_blur = true }) -- terminal.blur off\n"
}

func niriTerminal(t *TerminalLook) string {
	if t == nil || !t.Translucent || !t.Blur {
		return ""
	}
	return "window-rule { // terminal.blur\n    match app-id=r#\"" + terminalApps + "\"#\n    background-effect {\n        blur true\n    }\n}\n"
}

func luaEscape(s string) string {
	out := make([]byte, 0, len(s)+4)
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' || s[i] == '"' {
			out = append(out, '\\')
		}
		out = append(out, s[i])
	}
	return string(out)
}

// Refresh rewrites the managed file with the current monitors (the terminal look changed).
func (s *Service) Refresh() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	cur := s.previous
	if s.timer == nil {
		var err error
		if cur, err = s.Backend.Current(); err != nil {
			return err
		}
	}
	return s.writeManaged(cur)
}
