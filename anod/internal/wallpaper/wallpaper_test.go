package wallpaper

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeBin installs an executable shell script named name on PATH that logs
// its argv (one call per line) to dir/name.log, then runs body.
func fakeBin(t *testing.T, dir, name, body string) {
	t.Helper()
	script := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"" + filepath.Join(dir, name+".log") + "\"\n" + body + "\n"
	if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
}

func setup(t *testing.T) (bin, home string, p *Pipeline) {
	t.Helper()
	bin, home = t.TempDir(), t.TempDir()
	t.Setenv("PATH", bin)
	t.Setenv("HOME", home)
	fakeBin(t, bin, "awww", "exit 0")
	fakeBin(t, bin, "matugen", `printf '{"colors":{"primary":{"default":{"color":"#abcdef"}},"surface":{"default":{"color":"#111111"}}}}'`)
	p = &Pipeline{ColorsPath: filepath.Join(home, "state/colors.json"), StatePath: filepath.Join(home, "state/wallpaper.json")}
	return
}

func image(t *testing.T, dir, name string) string {
	p := filepath.Join(dir, name)
	os.MkdirAll(filepath.Dir(p), 0o755)
	os.WriteFile(p, []byte("x"), 0o644)
	return p
}

func TestApplyRunsChainInOrder(t *testing.T) {
	bin, home, p := setup(t)
	order := filepath.Join(home, "order")
	fakeBin(t, bin, "wal", "echo wal >> "+order)
	fakeBin(t, bin, "swaync-client", "echo swaync >> "+order)
	img := image(t, home, "pics/a b'$(touch pwned).png") // hostile name: argv only
	res, err := p.Apply(context.Background(), Request{Image: img, Outputs: []string{"eDP-1"}}, Settings{
		Resize: "fit", Mode: "dark", Transition: "fade", DurationMs: 1500,
		Hooks: []Hook{
			{Name: "pywal", Enable: true, Command: []string{"wal", "-i", "{image}", "-n", "-q"}},
			{Name: "off", Enable: false, Command: []string{"wal"}},
			{Name: "swaync", Enable: true, Command: []string{"swaync-client", "--reload-css"}},
			{Name: "missing", Enable: true, Command: []string{"no-such-tool"}},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(home, "pwned")); err == nil {
		t.Fatal("image name was run by a shell")
	}
	aw, _ := os.ReadFile(filepath.Join(bin, "awww.log"))
	if !strings.Contains(string(aw), "img --resize fit --transition-type fade --transition-duration 1.50 --outputs eDP-1 -- "+img) {
		t.Fatalf("awww argv: %q", aw)
	}
	got, _ := os.ReadFile(order)
	if string(got) != "wal\nswaync\n" {
		t.Fatalf("hook order: %q", got)
	}
	names := []string{}
	for _, s := range res.Steps {
		names = append(names, s.Name+":"+map[bool]string{true: "ok", false: "x"}[s.OK]+s.Skipped)
	}
	want := "awww:ok matugen:ok pywal:ok off:xdisabled swaync:ok missing:xnot installed: no-such-tool"
	if strings.Join(names, " ") != want {
		t.Fatalf("steps:\n got %s\nwant %s", strings.Join(names, " "), want)
	}
	var colors map[string]any
	b, _ := os.ReadFile(p.ColorsPath)
	json.Unmarshal(b, &colors)
	if colors["primary"] != "#abcdef" || colors["darkmode"] != true {
		t.Fatalf("colors.json: %s", b)
	}
	if st := p.LoadState(); st.Resize != "fit" || st.Outputs["eDP-1"] != img {
		t.Fatalf("state: %+v", st)
	}
}

func TestFixedColourModeSkipsHooks(t *testing.T) {
	bin, home, p := setup(t)
	fakeBin(t, bin, "wal", "exit 0")
	img := image(t, home, "a.jpg")
	res, _ := p.Apply(context.Background(), Request{Image: img}, Settings{FixedColor: true,
		Hooks: []Hook{{Name: "pywal", Enable: true, Command: []string{"wal", "-i", "{image}"}}}})
	if res.Steps[len(res.Steps)-1].Skipped != "fixed colour mode" {
		t.Fatalf("%+v", res.Steps)
	}
	if _, err := os.Stat(filepath.Join(bin, "wal.log")); err == nil {
		t.Fatal("pywal ran in fixed mode")
	}
}

func TestHookTimeout(t *testing.T) {
	bin, home, p := setup(t)
	fakeBin(t, bin, "slow", "/usr/bin/sleep 5")
	img := image(t, home, "a.png")
	res, _ := p.Apply(context.Background(), Request{Image: img}, Settings{
		Hooks: []Hook{{Name: "slow", Enable: true, Command: []string{"slow"}, Timeout: 1}}})
	last := res.Steps[len(res.Steps)-1]
	if last.OK || !strings.Contains(last.Error, "timed out") {
		t.Fatalf("%+v", last)
	}
}

func TestRecolourCava(t *testing.T) {
	cfg := "[color]\nbackground = 'old'\n# gradient_color_1 = 'keep'\ngradient_color_1 = 'x'\ngradient = 1\n"
	out := string(RecolourCava([]byte(cfg), "#000", "#fff", map[string]string{"color2": "#222"}))
	want := "[color]\nbackground = '#000'\n# gradient_color_1 = 'keep'\ngradient_color_1 = '#222'\ngradient = 1\n"
	if out != want {
		t.Fatalf("got %q", out)
	}
}

func TestBagNoRepeatAndPersist(t *testing.T) {
	dir := t.TempDir()
	for _, n := range []string{"a.png", "b.jpg", "c.webp", "notes.txt"} {
		image(t, dir, n)
	}
	state := filepath.Join(t.TempDir(), "bag.json")
	seen := map[string]bool{}
	b := LoadBag(state, dir)
	for i := 0; i < 3; i++ {
		img := b.Next("")
		if seen[img] || img == "" || strings.HasSuffix(img, ".txt") {
			t.Fatalf("repeat or bad pick %q at %d", img, i)
		}
		seen[img] = true
		b = LoadBag(state, dir) // a restart keeps what's left
	}
	// The pass is done: the next deal refills and never repeats the last image first.
	b.Remaining = nil
	last := filepath.Join(dir, "c.webp")
	if n := b.Next(last); n == last {
		t.Fatal("repeated the last image across the refill")
	}
}

// The hook example in docs/wallpaper.md parses and runs.
func TestDocsHookExampleRuns(t *testing.T) {
	doc, err := os.ReadFile("../../../docs/wallpaper.md")
	if err != nil {
		t.Fatal(err)
	}
	i := strings.Index(string(doc), "### Example: your own hook")
	block := string(doc)[i:]
	block = block[strings.Index(block, "```json")+7:]
	block = block[:strings.Index(block, "```")]
	var h Hook
	if err := json.Unmarshal([]byte(block), &h); err != nil {
		t.Fatalf("example: %v\n%s", err, block)
	}
	bin, home, p := setup(t)
	fakeBin(t, bin, h.Command[0], "exit 0")
	img := image(t, home, "a.png")
	res, err := p.Apply(context.Background(), Request{Image: img}, Settings{Hooks: []Hook{h}})
	last := res.Steps[len(res.Steps)-1]
	if err != nil || last.Name != "notify" || !last.OK {
		t.Fatalf("%v %+v", err, last)
	}
	log, _ := os.ReadFile(filepath.Join(bin, h.Command[0]+".log"))
	if !strings.Contains(string(log), "Wallpaper "+img) {
		t.Fatalf("argv: %q", log)
	}
}

func TestWriteAtomicKeepsLinkAndMode(t *testing.T) {
	d := t.TempDir()
	real := filepath.Join(d, "real")
	link := filepath.Join(d, "link")
	if err := os.WriteFile(real, []byte("old"), 0o640); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}
	if err := writeAtomic(link, []byte("new")); err != nil {
		t.Fatal(err)
	}
	if fi, _ := os.Lstat(link); fi.Mode()&os.ModeSymlink == 0 {
		t.Fatal("link replaced by a file")
	}
	b, _ := os.ReadFile(real)
	fi, _ := os.Stat(real)
	if string(b) != "new" || fi.Mode().Perm() != 0o640 {
		t.Fatalf("got %q mode %o", b, fi.Mode().Perm())
	}
}

// A pick remembered for A comes back on A, not on B; the request's own
// options win over it; reset forgets it.
func TestPerWallpaperChoices(t *testing.T) {
	bin, home, p := setup(t)
	p.Choices = &Choices{Path: filepath.Join(home, "state/wallpaper-colors.json")}
	a, b := image(t, home, "a.png"), image(t, home, "b.png")
	s := Settings{Mode: "dark", SchemeType: "tonal-spot", PerWallpaper: true}
	if _, err := p.Choices.Set(a, Choice{SchemeType: "vibrant", Mode: "light"}, false); err != nil {
		t.Fatal(err)
	}
	scheme := func(img string, req Choice, s Settings) Result {
		t.Helper()
		res, err := p.Apply(context.Background(), Request{Image: img, Choice: req}, s)
		if err != nil {
			t.Fatal(err)
		}
		return res
	}
	if r := scheme(a, Choice{}, s); r.Scheme.SchemeType != "vibrant" || r.Scheme.Mode != "light" || !r.Custom {
		t.Fatalf("A: %+v custom=%v", r.Scheme, r.Custom)
	}
	if r := scheme(b, Choice{}, s); r.Scheme.SchemeType != "tonal-spot" || r.Scheme.Mode != "dark" || r.Custom {
		t.Fatalf("B: %+v", r.Scheme)
	}
	if r := scheme(a, Choice{Mode: "dark"}, s); r.Scheme.SchemeType != "vibrant" || r.Scheme.Mode != "dark" {
		t.Fatalf("A with request: %+v", r.Scheme)
	}
	log, _ := os.ReadFile(filepath.Join(bin, "matugen.log"))
	if !strings.Contains(string(log), "--mode light --type scheme-vibrant") {
		t.Fatalf("matugen never ran vibrant/light:\n%s", log)
	}
	s.PerWallpaper = false
	if r := scheme(a, Choice{}, s); r.Scheme.SchemeType != "tonal-spot" || r.Custom {
		t.Fatalf("A with perWallpaper off: %+v", r.Scheme)
	}
	if ch, _ := p.Choices.Set(a, Choice{Prefer: "darkness"}, true); ch != (Choice{Prefer: "darkness"}) {
		t.Fatalf("reset then pick: %+v", ch)
	}
	if ch, _ := p.Choices.Set(a, Choice{}, true); ch != (Choice{}) {
		t.Fatalf("reset: %+v", ch)
	}
	if _, ok := p.Choices.Get(a); ok {
		t.Fatal("reset left an entry")
	}
}

// With a colour output, a wallpaper for another output leaves the colours;
// the colour output's does, and a repeat comes from the palette cache.
func TestColorOutputAndCache(t *testing.T) {
	bin, home, p := setup(t)
	p.ColorCache = filepath.Join(home, "cache")
	a := image(t, home, "a.png")
	s := Settings{Mode: "dark", ColorOutput: "HDMI-A-1"}
	calls := func() int {
		b, _ := os.ReadFile(filepath.Join(bin, "matugen.log"))
		return strings.Count(string(b), "\n")
	}
	if r, _ := p.Apply(context.Background(), Request{Image: a, Outputs: []string{"eDP-1"}}, s); r.ColorImage != "" || calls() != 0 {
		t.Fatalf("other output made colours: %+v", r)
	}
	if r, _ := p.Apply(context.Background(), Request{Image: a, Outputs: []string{"HDMI-A-1"}}, s); r.ColorImage != a || calls() != 1 {
		t.Fatalf("colour output: %+v, %d calls", r, calls())
	}
	if p.ColorImage(s) != a || p.LoadState().Colors != a {
		t.Fatal("colour image not recorded")
	}
	if r, _ := p.Apply(context.Background(), Request{Image: a, ColorsOnly: true}, s); r.ColorImage != a || calls() != 1 {
		t.Fatalf("cache missed: %d calls", calls())
	}
}
