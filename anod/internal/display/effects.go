package display

// Pointer warping (Hyprland cursor:no_warps) and niri's xray, written into the
// managed file. Both default to the compositor's own behaviour, which writes nothing.

// Effects is what the managed file needs from cursor.warp and niri.xray.
type Effects struct {
	Warp bool // cursor.warp: the pointer moves with keyboard focus (Hyprland's default)
	Xray bool // niri.xray: translucent surfaces show only the wallpaper (niri/ano.kdl's choice)
}

func hyprEffects(e *Effects) string {
	if e == nil || e.Warp {
		return ""
	}
	return "hl.config({ cursor = { no_warps = true } }) -- cursor.warp off\n"
}

// hyprWarpLive is what a config reload would set, in both directions.
func hyprWarpLive(e *Effects) string {
	if e == nil {
		return ""
	}
	if e.Warp {
		return "hl.config({ cursor = { no_warps = false } })\n"
	}
	return hyprEffects(e)
}

// niriEffects: later rules override ano.kdl's xray, the blur they set stays
// (a rule changes only the properties it names).
func niriEffects(e *Effects) string {
	if e == nil || e.Xray {
		return ""
	}
	return "window-rule { // niri.xray off\n    background-effect {\n        xray false\n    }\n    popups {\n        background-effect {\n            xray false\n        }\n    }\n}\n" +
		"layer-rule { // niri.xray off\n    match namespace=r#\"^quickshell\"#\n    background-effect {\n        xray false\n    }\n}\n"
}

// RefreshEffects rewrites the managed file (niri reloads it itself) and, on
// Hyprland, sets cursor:no_warps live.
func (s *Service) RefreshEffects() error {
	if err := s.Refresh(); err != nil {
		return err
	}
	if s.Backend.Name() != "hyprland" || s.Effects == nil {
		return nil
	}
	return s.exec("hyprctl", "eval", hyprWarpLive(s.Effects()))
}
