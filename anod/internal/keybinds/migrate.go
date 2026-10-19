package keybinds

import (
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
}

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
			text, n := stripHyprBinds(string(data), lines)
			if file == p.HyprMain {
				text = strings.TrimRight(text, "\n") + "\n\n" + IncludeHyprland + "\n"
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
		edits[p.NiriMain] = strings.TrimRight(text, "\n") + "\n\n" + IncludeNiri + "\n"
		res.Moved[p.NiriMain] = n
	}

	// Live binds the defaults don't already give that compositor become overrides.
	var ov Overrides
	for _, b := range live {
		matched := false
		for _, x := range d.Binds {
			if x.Key() == b.Key() && x.On(b.Only) && Same(x, b) {
				matched = true
				break
			}
		}
		if !matched {
			ov.Binds = append(ov.Binds, b)
			res.Report = append(res.Report, fmt.Sprintf("kept your %s bind %s → %s", b.Only, b.Chord, b.Describe()))
		}
	}
	res.Overrides = len(ov.Binds)
	sort.Strings(res.Report)
	if dryRun {
		return res, nil
	}

	man := Manifest{At: now, Backups: map[string]string{}}
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
	if _, _, err := Generate(p, Effective(d, ov), d.Helpers); err != nil {
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
// (keybinds.json and the generated files stay, unused).
func Revert(p Paths) ([]string, error) {
	b, err := os.ReadFile(manifestPath(p))
	if err != nil {
		return nil, errors.New("no migration to revert")
	}
	var m Manifest
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
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
func stripHyprBinds(src string, lines []int) (string, int) {
	ls := strings.Split(src, "\n")
	drop := make([]bool, len(ls))
	n := 0
	seen := map[int]bool{}
	for _, line := range lines {
		if seen[line] {
			continue
		}
		seen[line] = true
		start, end := statementRange(ls, line)
		if start < 0 {
			continue
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
	return strings.Join(out, "\n"), n
}

// statementRange is the 0-based line range of the hl.bind(…) call that the
// stub reported at line (Lua reports a multi-line call at its last line).
func statementRange(ls []string, line int) (int, int) {
	for i := min(line-1, len(ls)-1); i >= 0; i-- {
		if !strings.Contains(ls[i], "hl.bind(") {
			continue
		}
		d := 0
		for j := i; j < len(ls); j++ {
			d += strings.Count(ls[j], "(") - strings.Count(ls[j], ")")
			if d <= 0 {
				if j >= line-1 {
					return i, j
				}
				break
			}
		}
	}
	return -1, -1
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
