package hub

// The static audit for code content. Ported from Ryoku's plugin validator
// (ryoku/cli/plugin_audit.go, https://github.com/Ryoku-dev/ryoku, GPL-3.0,
// the same licence as AnoShell): the rule set, the comment stripping and the
// command/host extraction, adapted to AnoShell widgets (declared hosts and
// commands come from the catalog entry; no Ryoku import rules). It reads
// bytes only and never runs anything from the item.

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Finding is one audit result; Line is 1-based, 0 for a whole-file finding.
type Finding struct {
	Rule     string `json:"rule"`
	File     string `json:"file"`
	Line     int    `json:"line"`
	Detail   string `json:"detail"`
	Severity string `json:"severity"` // "warn" | "high"
}

var highRules = map[string]bool{
	"symlink": true, "binary": true, "escalation": true, "pipe-shell": true,
	"config-write": true, "secrets-read": true,
}

// harmlessCommands may run without being declared.
var harmlessCommands = map[string]bool{
	"notify-send": true, "xdg-open": true, "wl-copy": true, "wl-paste": true,
	"date": true, "sleep": true, "cat": true, "ano": true,
}

var (
	escalationRe   = regexp.MustCompile(`\b(sudo|doas|su)\b`)
	pipeShellRe    = regexp.MustCompile(`(?:curl|wget|fetch)[^|\n]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh|dash|fish|python3?|perl)\b|eval\s+"?\$\((?:curl|wget)|(?:sh|bash|zsh)\s+(?:-c\s+)?["']?\$\((?:curl|wget)|(?:sh|bash)\s+<\(\s*(?:curl|wget)`)
	secretLitRe    = regexp.MustCompile(`(?:sk|ghp|gho|xox[abp])-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY`)
	cmdArrayRe     = regexp.MustCompile(`command\s*:\s*\[\s*([^,\]\n]+)`)
	execDetachedRe = regexp.MustCompile(`(?:execDetached|startDetached)\s*\(\s*\[\s*([^,\]\n]+)`)
	hostRe         = regexp.MustCompile(`(?:https?|wss?)://([^/"'\s` + "`" + `]+)`)
	shcArrayRe     = regexp.MustCompile(`["'](?:sh|bash)["']\s*,\s*["']-c["']\s*,\s*([^\]\)]+)`)
	shcInlineRe    = regexp.MustCompile(`\b(?:sh|bash)\s+-c\b(.*)`)
	outsideWriteRe = regexp.MustCompile(`~/\.config/|\$HOME/\.|homePath\s*\+\s*["']/\.`)
	cmdPunctRe     = regexp.MustCompile(`["'\[\](),+]`)
)

// Audit checks every file under root. hosts and commands are what the item
// declares; anything else it contacts or runs is reported.
func Audit(root string, hosts, commands []string) []Finding {
	out := []Finding{}
	add := func(rule, file string, line int, detail string) {
		sev := "warn"
		if highRules[rule] {
			sev = "high"
		}
		out = append(out, Finding{rule, file, line, detail, sev})
	}
	filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(root, p)
		rel = filepath.ToSlash(rel)
		if d.Type()&fs.ModeSymlink != 0 {
			add("symlink", rel, 0, "a symlink; it could point anywhere on your system")
			return nil
		}
		if !d.Type().IsRegular() {
			add("binary", rel, 0, "not a regular file")
			return nil
		}
		if fi, err := d.Info(); err == nil && fi.Mode()&0o111 != 0 {
			add("executable", rel, 0, "marked executable")
		}
		switch strings.ToLower(filepath.Ext(p)) {
		case ".so", ".dylib", ".exe", ".dll", ".node":
			add("binary", rel, 0, "a compiled binary; widgets ship QML and scripts only")
			return nil
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return nil
		}
		if hasBinaryMagic(b) {
			add("binary", rel, 0, "a compiled binary; widgets ship QML and scripts only")
			return nil
		}
		auditFile(rel, b, hosts, commands, add)
		return nil
	})
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].File != out[j].File {
			return out[i].File < out[j].File
		}
		if out[i].Line != out[j].Line {
			return out[i].Line < out[j].Line
		}
		return out[i].Rule < out[j].Rule
	})
	return out
}

func auditFile(p string, content []byte, hosts, commands []string, add func(rule, file string, line int, detail string)) {
	auditText(p, classify(p, content), content, hosts, commands, add)
}

func auditText(p, class string, content []byte, hosts, commands []string, add func(rule, file string, line int, detail string)) {
	raw := strings.Split(string(content), "\n")
	for i, ln := range raw {
		if secretLitRe.MatchString(ln) {
			add("secret", p, i+1, "looks like a hardcoded key or token")
		}
	}
	if class != "qml" && class != "js" && class != "sh" && class != "py" {
		return
	}
	if bytes.IndexByte(content, 0) >= 0 {
		return
	}
	qmlLike := class == "qml" || class == "js"
	for i, code := range codeText(raw, class) {
		line := i + 1
		if m := escalationRe.FindString(code); m != "" {
			add("escalation", p, line, fmt.Sprintf("uses %q: asks for root", m))
		}
		if idx := strings.Index(code, "pkexec"); idx >= 0 && !pkexecDeclared(code[idx:], commands) {
			add("escalation", p, line, "runs pkexec without declaring that exact command")
		}
		if pipeShellRe.MatchString(code) {
			add("pipe-shell", p, line, "downloads code and runs it")
		}
		for _, w := range []struct{ needle, what string }{
			{"~/.ssh", "~/.ssh"}, {"/.ssh/", "~/.ssh"}, {"/etc/", "/etc"},
			{"anoshell/config.json", "the shell config"}, {"quickshell/ano/", "the shell's own files"},
			{".bashrc", "a shell rc file"}, {".zshrc", "a shell rc file"}, {"config.fish", "a shell rc file"},
			{".profile", "a shell rc file"}, {"hypr/", "the compositor config"}, {"niri/config", "the compositor config"},
		} {
			if strings.Contains(code, w.needle) {
				add("config-write", p, line, "touches "+w.what)
				break
			}
		}
		if strings.Contains(code, "anoshell/secrets") || strings.Contains(code, "/secrets/") {
			add("secrets-read", p, line, "reads the secrets folder (API keys)")
		}
		if qmlLike {
			for _, name := range extractCommands(code) {
				if !harmlessCommands[name] && !declared(name, commands) {
					add("undeclared-command", p, line, fmt.Sprintf("runs %q, which the item doesn't declare", name))
				}
			}
		}
		for _, m := range hostRe.FindAllStringSubmatch(code, -1) {
			host := strings.ToLower(m[1])
			if i := strings.LastIndexByte(host, '@'); i >= 0 {
				host = host[i+1:]
			}
			if i := strings.IndexByte(host, ':'); i >= 0 {
				host = host[:i]
			}
			if host != "" && !declaredHost(host, hosts) {
				add("undeclared-host", p, line, fmt.Sprintf("contacts %q, which the item doesn't declare", host))
			}
		}
		if isDynamicShell(code) {
			add("dynamic-shell", p, line, "sh -c with a built-up argument (injection risk)")
		}
		if outsideWriteRe.MatchString(code) {
			add("outside-write", p, line, "uses paths in your home folder outside its own")
		}
	}
}

func declared(name string, commands []string) bool {
	for _, c := range commands {
		if f := strings.Fields(c); len(f) > 0 && path.Base(f[0]) == name {
			return true
		}
	}
	return false
}

func declaredHost(host string, hosts []string) bool {
	for _, h := range hosts {
		h = strings.ToLower(strings.TrimSpace(h))
		if h == host || strings.HasPrefix(h, "*.") && strings.HasSuffix(host, h[1:]) {
			return true
		}
	}
	return false
}

// pkexecDeclared: a declared command starting with pkexec, normalised, is a
// prefix of the code from the pkexec token on.
func pkexecDeclared(fromPkexec string, commands []string) bool {
	norm := normalizeCmd(fromPkexec)
	for _, c := range commands {
		c = normalizeCmd(c)
		if strings.HasPrefix(c, "pkexec ") && strings.HasPrefix(norm, c) {
			return true
		}
	}
	return false
}

func normalizeCmd(s string) string {
	return strings.Join(strings.Fields(cmdPunctRe.ReplaceAllString(s, " ")), " ")
}

func classify(p string, content []byte) string {
	switch strings.ToLower(filepath.Ext(p)) {
	case ".qml":
		return "qml"
	case ".js", ".mjs":
		return "js"
	case ".sh", ".bash", ".zsh":
		return "sh"
	case ".py":
		return "py"
	case ".json":
		return "json"
	}
	if bytes.HasPrefix(content, []byte("#!")) {
		first, _, _ := bytes.Cut(content, []byte("\n"))
		if bytes.Contains(first, []byte("python")) {
			return "py"
		}
		if bytes.Contains(first, []byte("sh")) {
			return "sh"
		}
	}
	return "other"
}

func hasBinaryMagic(b []byte) bool {
	if len(b) < 4 {
		return false
	}
	for _, m := range [][]byte{{0x7f, 'E', 'L', 'F'}, {0xFE, 0xED, 0xFA, 0xCE}, {0xFE, 0xED, 0xFA, 0xCF},
		{0xCE, 0xFA, 0xED, 0xFE}, {0xCF, 0xFA, 0xED, 0xFE}, {0xCA, 0xFE, 0xBA, 0xBE}, {'M', 'Z'}} {
		if bytes.HasPrefix(b, m) {
			return true
		}
	}
	return false
}

// codeText blanks comments, keeping line numbers.
func codeText(raw []string, class string) []string {
	out := make([]string, len(raw))
	if class == "sh" || class == "py" {
		for i, ln := range raw {
			out[i] = stripHashComment(ln)
		}
		return out
	}
	in := false
	for i, ln := range raw {
		out[i], in = stripCLine(ln, in)
	}
	return out
}

func stripHashComment(ln string) string {
	var b strings.Builder
	var quote byte
	prevSpace := true
	for i := 0; i < len(ln); i++ {
		c := ln[i]
		if quote != 0 {
			b.WriteByte(c)
			if c == quote {
				quote = 0
			}
			prevSpace = false
			continue
		}
		if c == '\'' || c == '"' {
			quote = c
		} else if c == '#' && prevSpace {
			return b.String()
		}
		b.WriteByte(c)
		prevSpace = c == ' ' || c == '\t'
	}
	return b.String()
}

func stripCLine(ln string, inBlock bool) (string, bool) {
	var b strings.Builder
	var quote byte
	for i := 0; i < len(ln); i++ {
		c := ln[i]
		if inBlock {
			if c == '*' && i+1 < len(ln) && ln[i+1] == '/' {
				b.WriteString("  ")
				i++
				inBlock = false
			} else {
				b.WriteByte(' ')
			}
			continue
		}
		if quote != 0 {
			b.WriteByte(c)
			if c == '\\' && i+1 < len(ln) {
				i++
				b.WriteByte(ln[i])
				continue
			}
			if c == quote {
				quote = 0
			}
			continue
		}
		switch {
		case c == '"' || c == '\'' || c == '`':
			quote = c
			b.WriteByte(c)
		case c == '/' && i+1 < len(ln) && ln[i+1] == '/':
			return b.String(), false
		case c == '/' && i+1 < len(ln) && ln[i+1] == '*':
			b.WriteString("  ")
			i++
			inBlock = true
		default:
			b.WriteByte(c)
		}
	}
	return b.String(), inBlock
}

// extractCommands returns argv[0] of each Process command array and
// execDetached call on a line (string literals only).
func extractCommands(code string) []string {
	var names []string
	for _, re := range []*regexp.Regexp{cmdArrayRe, execDetachedRe} {
		for _, m := range re.FindAllStringSubmatch(code, -1) {
			s := strings.TrimSpace(m[1])
			if len(s) < 2 || (s[0] != '"' && s[0] != '\'') {
				continue
			}
			end := strings.IndexByte(s[1:], s[0])
			if end <= 0 {
				continue
			}
			names = append(names, path.Base(s[1:1+end]))
		}
	}
	return names
}

func isDynamicShell(code string) bool {
	for _, m := range shcArrayRe.FindAllStringSubmatch(code, -1) {
		arg := strings.TrimRight(strings.TrimSpace(m[1]), " )]")
		if !singleLiteral(arg) {
			return true
		}
	}
	m := shcInlineRe.FindStringSubmatch(code)
	return m != nil && strings.Contains(m[1], "+")
}

func singleLiteral(s string) bool {
	if len(s) < 2 || (s[0] != '"' && s[0] != '\'') || s[len(s)-1] != s[0] {
		return false
	}
	return !strings.ContainsRune(s[1:len(s)-1], rune(s[0]))
}
