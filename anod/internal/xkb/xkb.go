// Package xkb reads the XKB layout catalogue (rules/evdev.xml): every layout
// and its variants with their descriptions, for Settings' layout picker
// (spec system-integration, keyboard layout catalogue).
package xkb

import (
	"encoding/xml"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// Path is where xkeyboard-config installs the catalogue.
const Path = "/usr/share/X11/xkb/rules/evdev.xml"

// Layout is one layout, or one variant of it (Variant set).
type Layout struct {
	Layout      string `json:"layout"`
	Variant     string `json:"variant"`
	Short       string `json:"short"` // e.g. "en", "fr"
	Description string `json:"description"`
}

type configItem struct {
	Name        string `xml:"name"`
	Short       string `xml:"shortDescription"`
	Description string `xml:"description"`
}

type registry struct {
	Layouts []struct {
		Item     configItem `xml:"configItem"`
		Variants []struct {
			Item configItem `xml:"configItem"`
		} `xml:"variantList>variant"`
	} `xml:"layoutList>layout"`
}

// Catalogue parses the catalogue at path: layouts in file order, each
// followed by its variants.
func Catalogue(path string) ([]Layout, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var r registry
	if err := xml.Unmarshal(b, &r); err != nil {
		return nil, err
	}
	var out []Layout
	for _, l := range r.Layouts {
		out = append(out, Layout{Layout: l.Item.Name, Short: l.Item.Short, Description: l.Item.Description})
		for _, v := range l.Variants {
			short := v.Item.Short
			if short == "" {
				short = l.Item.Short
			}
			out = append(out, Layout{Layout: l.Item.Name, Variant: v.Item.Name, Short: short, Description: v.Item.Description})
		}
	}
	return out, nil
}

var code = regexp.MustCompile(`^[A-Za-z0-9_-]*$`)

// Join checks each pick is in the catalogue and returns the comma lists the
// compositors take: "us,fr" and ",azerty".
func Join(cat []Layout, picks []Layout) (layouts, variants string, err error) {
	known := map[string]bool{}
	for _, l := range cat {
		known[l.Layout+"("+l.Variant+")"] = true
	}
	if len(picks) == 0 {
		return "", "", fmt.Errorf("no layouts")
	}
	var ls, vs []string
	for _, p := range picks {
		if !code.MatchString(p.Layout) || p.Layout == "" || !code.MatchString(p.Variant) || !known[p.Layout+"("+p.Variant+")"] {
			return "", "", fmt.Errorf("unknown layout %q variant %q", p.Layout, p.Variant)
		}
		ls = append(ls, p.Layout)
		vs = append(vs, p.Variant)
	}
	return strings.Join(ls, ","), strings.Join(vs, ","), nil
}
