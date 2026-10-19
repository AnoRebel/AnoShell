package keybinds

import (
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// Manifest records a migration so --revert can undo it byte for byte.
type Manifest struct {
	At      time.Time         `json:"at"`
	Backups map[string]string `json:"backups"` // config file → its backup
	// sha256 of each file as migration left it: revert won't overwrite later edits.
	Written map[string]string `json:"written"`
}

func sha(b []byte) string { return fmt.Sprintf("%x", sha256.Sum256(b)) }

func manifestPath(p Paths) string {
	return filepath.Join(filepath.Dir(p.Overrides), "keybinds-migration.json")
}

// MigrateResult says what a migration did (or would do, dry run).
type MigrateResult struct {
	Backups   map[string]string `json:"backups"`
	Moved     map[string]int    `json:"moved"`     // config file → binds taken out
	Overrides int               `json:"overrides"` // live binds that differ from the defaults
	Report    []string          `json:"report"`
}

// Migrate moves the binds out of the user's compositor configs into ano's set:
// backups first, live binds that differ from the defaults become overrides,
// bind statements leave the configs, one include line goes in, and the
// managed files are generated. Configs that don't exist are skipped.
func Migrate(p Paths, d Defaults, now time.Time, dryRun bool) (MigrateResult, error) {
	res := MigrateResult{Backups: map[string]string{}, Moved: map[string]int{}}
	if _, err := os.Stat(manifestPath(p)); err == nil {
		return res, errors.New("already migrated (ano keybinds migrate --revert first)")
	}
	stamp := now.Format("20060102-150405")
	edits := map[string]string{} // file → new text
	var live []Bind
	onHypr, onNiri := map[string]bool{}, map[string]bool{}

	if _, err := os.Stat(p.HyprMain); err == nil {
		src, _ := os.ReadFile(p.HyprMain)
		if hasLine(string(src), IncludeHyprland) {
			return res, fmt.Errorf("%s already includes ano's binds", p.HyprMain)
		}
		recs, err := readHyprRecords(p.HyprMain)
		if err != nil {
			return res, err
		}
		byFile := map[string][]int{}
		for i, b := range recordsToBinds(recs) {
			r := recs[i]
			b.Only = "hyprland"
			live = append(live, b)
			onHypr[b.Key()] = true
			byFile[r.File] = append(byFile[r.File], r.Line)
		}
		for file, lines := range byFile {
			data, err := os.ReadFile(file)
			if err != nil {
				return res, err
			}
			text, n, err := stripHyprBinds(string(data), lines)
			if err != nil {
				return res, fmt.Errorf("%s: %w", file, err)
			}
			if file == p.HyprMain {
				text = strings.TrimRight(text, "\n") + "\n\n" + IncludeHyprlandManaged + "\n" + IncludeHyprland + "\n"
			}
			edits[file] = text
			res.Moved[file] = n
		}
	}
	if _, err := os.Stat(p.NiriMain); err == nil {
		src, _ := os.ReadFile(p.NiriMain)
		if hasLine(string(src), IncludeNiri) {
			return res, fmt.Errorf("%s already includes ano's binds", p.NiriMain)
		}
		nb, err := ReadNiri(p.NiriMain)
		if err != nil {
			return res, err
		}
		for _, b := range nb {
			b.Only = "niri"
			live = append(live, b)
			onNiri[b.Key()] = true
		}
		text, n := stripNiriBinds(string(src))
		edits[p.NiriMain] = strings.TrimRight(text, "\n") + "\n\n" + IncludeNiriManaged + "\n" + IncludeNiri + "\n"
		res.Moved[p.NiriMain] = n
	}

	// Live binds the defaults don't already give that compositor become
	// overrides. An override replaces every default on its chord, so once one
	// bind on a chord is kept, all of your binds on that chord are.
	var ov Overrides
	chordKept := map[string]bool{} // compositor + key
	for _, b := range live {
		matched := false
		for _, x := range d.Binds {
			if x.Key() == b.Key() && x.On(b.Only) && Same(x, b) {
				matched = true
				break
			}
		}
		if !matched {
			chordKept[b.Only+"\x00"+b.Key()] = true
		}
	}
	for _, b := range live {
		if chordKept[b.Only+"\x00"+b.Key()] {
			ov.Binds = append(ov.Binds, b)
			res.Report = append(res.Report, fmt.Sprintf("kept your %s bind %s → %s", b.Only, b.Chord, b.Describe()))
		}
	}
	res.Overrides = len(ov.Binds)
	if src, err := os.ReadFile(p.HyprMain); err == nil {
		ov.HyprHelpers = Helpers(string(src), ov.Binds)
	}
	sort.Strings(res.Report)
	if dryRun {
		return res, nil
	}

	man := Manifest{At: now, Backups: map[string]string{}, Written: map[string]string{}}
	for file := range edits {
		bak := file + ".ano-backup-" + stamp
		data, err := os.ReadFile(file)
		if err != nil {
			return res, err
		}
		if err := os.WriteFile(bak, data, 0o600); err != nil {
			return res, err
		}
		man.Backups[file], res.Backups[file] = bak, bak
		man.Written[file] = sha([]byte(edits[file]))
	}
	mb, _ := json.MarshalIndent(man, "", "  ")
	if err := os.MkdirAll(filepath.Dir(manifestPath(p)), 0o755); err != nil {
		return res, err
	}
	if err := writeAtomic(manifestPath(p), mb, 0o644); err != nil {
		return res, err
	}
	if err := SaveOverrides(p.Overrides, ov); err != nil {
		return res, err
	}
	if _, _, err := Generate(p, Effective(d, ov), AllHelpers(d, ov)); err != nil {
		return res, err
	}
	for file, text := range edits {
		fi, _ := os.Stat(file)
		if err := writeAtomic(file, []byte(text), fi.Mode().Perm()); err != nil {
			return res, err
		}
	}
	return res, nil
}

// Revert puts the backed-up configs back exactly and forgets the migration
// (keybinds.json and the generated files stay, unused). A config edited since
// the migration is not overwritten unless force; then the edited copy is
// saved next to it first.
func Revert(p Paths, force bool) ([]string, error) {
	b, err := os.ReadFile(manifestPath(p))
	if err != nil {
		return nil, errors.New("no migration to revert")
	}
	var m Manifest
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	for file := range m.Backups {
		cur, err := os.ReadFile(file)
		if err != nil || m.Written[file] == "" || sha(cur) == m.Written[file] {
			continue
		}
		if !force {
			return nil, fmt.Errorf("%s changed since the migration; revert with --force to replace it (your edited copy is saved next to it)", file)
		}
		if err := os.WriteFile(file+".edited-"+time.Now().Format("20060102-150405"), cur, 0o600); err != nil {
			return nil, err
		}
	}
	var done []string
	for file, bak := range m.Backups {
		data, err := os.ReadFile(bak)
		if err != nil {
			return done, err
		}
		perm := os.FileMode(0o644)
		if fi, err := os.Stat(file); err == nil {
			perm = fi.Mode().Perm()
		}
		if err := writeAtomic(file, data, perm); err != nil {
			return done, err
		}
		done = append(done, file)
	}
	return done, os.Remove(manifestPath(p))
}

func readHyprRecords(path string) ([]hyprRecord, error) {
	var recs []hyprRecord
	out, err := runStub(path)
	if err != nil {
		return nil, err
	}
	return recs, json.Unmarshal(out, &recs)
}

// stripHyprBinds removes the hl.bind statements whose calls are on the given
// lines (as the stub reports them); a statement inside a loop is removed once.
// Strings and comments are skipped when matching parentheses. A bind that
// can't be cut out cleanly (other code on its lines) stops the migration:
// guessing could delete config that isn't a bind.
func stripHyprBinds(src string, lines []int) (string, int, error) {
	ls := strings.Split(src, "\n")
	code := strings.Split(maskLua(src), "\n") // same lines, strings and comments blanked
	drop := make([]bool, len(ls))
	n := 0
	seen := map[int]bool{}
	for _, line := range lines {
		if seen[line] {
			continue
		}
		seen[line] = true
		start, end, err := statementRange(code, line)
		if err != nil {
			return "", 0, err
		}
		for i := start; i <= end; i++ {
			drop[i] = true
		}
		n++
	}
	var out []string
	for i, l := range ls {
		if !drop[i] {
			out = append(out, l)
		}
	}
	return strings.Join(out, "\n"), n, nil
}

// statementRange is the 0-based line range of the hl.bind(…) call that the
// stub reported at line (1-based; Lua may report a multi-line call at a later
// line), found in code with strings and comments masked out.
func statementRange(code []string, line int) (int, int, error) {
	at := line - 1
	for i := min(at, len(code)-1); i >= 0; i-- {
		col := strings.Index(code[i], "hl.bind(")
		if col < 0 {
			continue
		}
		// Find where this call's parenthesis closes.
		depth, j, endCol := 0, i, -1
		for ; j < len(code) && endCol < 0; j++ {
			from := 0
			if j == i {
				from = col + len("hl.bind")
			}
			for k := from; k < len(code[j]); k++ {
				switch code[j][k] {
				case '(':
					depth++
				case ')':
					depth--
					if depth == 0 {
						endCol = k
					}
				}
				if endCol >= 0 {
					break
				}
			}
		}
		j--
		if endCol < 0 || j < at {
			continue // not the call that covers the reported line
		}
		if strings.TrimSpace(code[i][:col]) != "" || strings.Trim(code[j][endCol+1:], " \t;") != "" {
			return -1, -1, fmt.Errorf("line %d: the bind shares its line with other code; move it to its own line(s) and run the migration again", i+1)
		}
		return i, j, nil
	}
	return -1, -1, fmt.Errorf("line %d: could not find the hl.bind statement to move", line)
}

// maskLua blanks Lua strings and comments (keeping newlines), so parentheses
// and keywords inside them don't count.
func maskLua(src string) string {
	b := []byte(src)
	blank := func(from, to int) {
		for k := from; k < to && k < len(b); k++ {
			if b[k] != '\n' {
				b[k] = ' '
			}
		}
	}
	// longBracket returns the length of "[==[" at i (0 if none) and its level.
	longBracket := func(i int) (int, int) {
		if i >= len(b) || b[i] != '[' {
			return 0, 0
		}
		j := i + 1
		for j < len(b) && b[j] == '=' {
			j++
		}
		if j < len(b) && b[j] == '[' {
			return j - i + 1, j - i - 1
		}
		return 0, 0
	}
	closeLong := func(i, level int) int {
		end := "]" + strings.Repeat("=", level) + "]"
		if k := strings.Index(string(b[i:]), end); k >= 0 {
			return i + k + len(end)
		}
		return len(b)
	}
	for i := 0; i < len(b); {
		switch {
		case b[i] == '-' && i+1 < len(b) && b[i+1] == '-':
			if n, lvl := longBracket(i + 2); n > 0 {
				e := closeLong(i+2+n, lvl)
				blank(i, e)
				i = e
			} else {
				e := i
				for e < len(b) && b[e] != '\n' {
					e++
				}
				blank(i, e)
				i = e
			}
		case b[i] == '"' || b[i] == '\'':
			q, e := b[i], i+1
			for e < len(b) && b[e] != q && b[e] != '\n' {
				if b[e] == '\\' {
					e++
				}
				e++
			}
			blank(i, e+1)
			i = e + 1
		default:
			if n, lvl := longBracket(i); n > 0 {
				e := closeLong(i+n, lvl)
				blank(i, e)
				i = e
			} else {
				i++
			}
		}
	}
	return string(b)
}

var niriBindsStart = regexp.MustCompile(`^binds\s*\{`)

// stripNiriBinds removes the top-level binds {} blocks and counts their binds.
func stripNiriBinds(src string) (string, int) {
	ls := strings.Split(src, "\n")
	var out []string
	n := 0
	for i := 0; i < len(ls); i++ {
		if !niriBindsStart.MatchString(strings.TrimSpace(ls[i])) || strings.HasPrefix(ls[i], " ") {
			out = append(out, ls[i])
			continue
		}
		depth := 0
		for ; i < len(ls); i++ {
			t := strings.TrimSpace(ls[i])
			if depth == 1 && t != "" && !strings.HasPrefix(t, "//") && t != "}" {
				n++
			}
			depth += strings.Count(ls[i], "{") - strings.Count(ls[i], "}")
			if depth <= 0 {
				break
			}
		}
	}
	return strings.Join(out, "\n"), n
}
