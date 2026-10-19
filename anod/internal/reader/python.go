package reader

import (
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// The legacy Python servers (novelmangareader's, in ano/scripts/reader/),
// selectable per provider with reader.providers.<kind>.backend: python until
// the Go providers have passed live verification. anod starts one lazily on
// a free port and proxies /<token>/<kind>/… to it, so the shell sees one
// backend either way.

var pyScripts = map[string][]string{
	"anime": {"anime_server.py"},
	"manga": {"manga_server.py"},
	"novel": {"novel_server", "main.py"},
}

type pyBackend struct {
	cmd   *exec.Cmd
	proxy *httputil.ReverseProxy
	done  chan struct{}
}

func freePort() (int, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port, nil
}

// ensurePython (mu held) starts kind's Python server and waits for /health.
func (s *Service) ensurePython(kind string) error {
	if p := s.py[kind]; p != nil {
		select {
		case <-p.done: // exited; start a new one
		default:
			return nil
		}
	}
	py := s.settings.Python
	if py == "" {
		py = "python3"
	}
	script := filepath.Join(append([]string{s.settings.ScriptsDir}, pyScripts[kind]...)...)
	if _, err := os.Stat(script); err != nil {
		return fmt.Errorf("python backend for %s: %w", kind, err)
	}
	port, err := freePort()
	if err != nil {
		return err
	}
	cmd := exec.Command(py, script, "--port", fmt.Sprint(port))
	cmd.Env = append(os.Environ(),
		"ANO_READER_PORT="+fmt.Sprint(port),
		// The servers' image URLs point back through anod (token and all).
		"ANO_READER_IMAGE_BASE="+s.base+kind)
	cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM} // dies with anod
	if s.Logf != nil {
		cmd.Stdout, cmd.Stderr = logWriter{s, kind}, logWriter{s, kind}
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("python backend for %s: %w", kind, err)
	}
	done := make(chan struct{})
	go func() { cmd.Wait(); close(done) }()

	target, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
	prefix := "/" + s.token + "/" + kind
	rp := &httputil.ReverseProxy{Rewrite: func(r *httputil.ProxyRequest) {
		r.SetURL(target)
		r.Out.URL.Path = strings.TrimPrefix(r.In.URL.Path, prefix)
		r.Out.URL.RawPath = ""
	}}
	// ponytail: holds the service lock while Python boots (up to 15 s); other
	// panels' requests wait meanwhile. Fallback-only path.
	deadline := time.Now().Add(15 * time.Second)
	for {
		resp, err := http.Get(target.String() + "/health")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				break
			}
		}
		select {
		case <-done:
			return fmt.Errorf("python backend for %s exited during startup (see anod.log)", kind)
		case <-time.After(200 * time.Millisecond):
		}
		if time.Now().After(deadline) {
			cmd.Process.Kill()
			return fmt.Errorf("python backend for %s did not answer within 15 s", kind)
		}
	}
	s.py[kind] = &pyBackend{cmd: cmd, proxy: rp, done: done}
	s.logf("python backend for %s on port %d", kind, port)
	return nil
}

func (p *pyBackend) stop() {
	if p.cmd.Process == nil {
		return
	}
	p.cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-p.done:
	case <-time.After(2 * time.Second):
		p.cmd.Process.Kill()
		<-p.done
	}
}

type logWriter struct {
	s    *Service
	kind string
}

func (l logWriter) Write(b []byte) (int, error) {
	for _, line := range strings.Split(strings.TrimRight(string(b), "\n"), "\n") {
		l.s.logf("python %s: %s", l.kind, line)
	}
	return len(b), nil
}
