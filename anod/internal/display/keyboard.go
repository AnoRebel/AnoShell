package display

import (
	"fmt"
	"regexp"
)

// Keyboard is the ordered XKB layouts as the compositors take them: comma
// lists, e.g. "us,fr" and ",azerty" (built by internal/xkb.Join).
type Keyboard struct {
	Layouts  string `json:"layouts"`
	Variants string `json:"variants"`
}

var xkbList = regexp.MustCompile(`^[A-Za-z0-9_,-]*$`)

func validKeyboard(k Keyboard) error {
	if k.Layouts == "" || !xkbList.MatchString(k.Layouts) || !xkbList.MatchString(k.Variants) {
		return fmt.Errorf("bad layouts %q / variants %q", k.Layouts, k.Variants)
	}
	return nil
}

// hyprKeyboard is the input block's two keys, as a Lua call: in the managed
// file, and evaluated live (only these keys, nothing else of input).
func hyprKeyboard(k Keyboard) string {
	return fmt.Sprintf("hl.config({ input = { kb_layout = %q, kb_variant = %q } })", k.Layouts, k.Variants)
}

// niriKeyboard merges into the user's input section (niri merges included
// sections field by field).
func niriKeyboard(k Keyboard) string {
	return fmt.Sprintf("input {\n    keyboard {\n        xkb {\n            layout %q\n            variant %q\n        }\n    }\n}\n", k.Layouts, k.Variants)
}

// SetKeyboard applies the layouts live (Hyprland: eval of input's kb_layout
// and kb_variant; niri reloads the managed file it includes) and persists
// them in the managed file.
func (s *Service) SetKeyboard(k Keyboard) error {
	if err := validKeyboard(k); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.keyboard = &k
	if s.Backend.Name() == "hyprland" {
		if err := s.exec("hyprctl", "eval", hyprKeyboard(k)); err != nil {
			s.logf("hyprctl eval keyboard: %v", err)
		}
	}
	cur := s.previous
	if s.timer == nil {
		var err error
		if cur, err = s.Backend.Current(); err != nil {
			return err
		}
	}
	return s.writeManaged(cur)
}
