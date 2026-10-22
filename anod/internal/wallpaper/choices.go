package wallpaper

import (
	"encoding/json"
	"os"
	"sync"
)

// Choice is the colour options picked for one wallpaper. Empty fields fall
// back to the defaults in the shell config.
type Choice struct {
	SchemeType string `json:"schemeType,omitempty"`
	Prefer     string `json:"prefer,omitempty"`
	Mode       string `json:"mode,omitempty"` // dark | light
}

func (c Choice) empty() bool { return c == Choice{} }

// over returns s with c's non-empty fields applied.
func (c Choice) over(s Settings) Settings {
	if c.SchemeType != "" {
		s.SchemeType = c.SchemeType
	}
	if c.Prefer != "" {
		s.Prefer = c.Prefer
	}
	if c.Mode == "dark" || c.Mode == "light" {
		s.Mode = c.Mode
	}
	return s
}

// Choices remembers colour picks per wallpaper (absolute path), in a JSON
// file under the state dir.
// ponytail: entries for deleted or renamed files stay; prune when the file grows.
type Choices struct {
	Path string
	mu   sync.Mutex
}

func (c *Choices) load() map[string]Choice {
	m := map[string]Choice{}
	if b, err := os.ReadFile(c.Path); err == nil {
		_ = json.Unmarshal(b, &m)
	}
	return m
}

// Get returns the picks remembered for img.
func (c *Choices) Get(img string) (Choice, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	ch, ok := c.load()[img]
	return ch, ok
}

// Set merges pick's non-empty fields into img's entry; reset drops the entry
// first. Returns what is remembered now.
func (c *Choices) Set(img string, pick Choice, reset bool) (Choice, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	m := c.load()
	ch := m[img]
	if reset {
		ch = Choice{}
	}
	ch = Choice{SchemeType: or(pick.SchemeType, ch.SchemeType), Prefer: or(pick.Prefer, ch.Prefer), Mode: or(pick.Mode, ch.Mode)}
	if ch.empty() {
		delete(m, img)
	} else {
		m[img] = ch
	}
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return ch, err
	}
	return ch, writeAtomic(c.Path, b)
}

func or(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
