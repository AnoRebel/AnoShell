// Package ipc is anod's control socket: newline-delimited JSON over a
// per-user Unix socket.
//
//	request   {"v":1,"id":7,"method":"status","params":{...}}
//	response  {"id":7,"result":...}  or  {"id":7,"error":{"code":"...","message":"..."}}
//	event     {"event":"theme_mode_changed","data":{...}}   (after "subscribe")
//
// The socket lives in a 0700 directory and is itself 0600, so only the owning
// user can connect.
package ipc

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"ano/anod/internal/version"
)

type Request struct {
	V      int             `json:"v"`
	ID     json.RawMessage `json:"id,omitempty"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params,omitempty"`
}

type Response struct {
	ID     json.RawMessage `json:"id,omitempty"`
	Result any             `json:"result,omitempty"`
	Error  *Error          `json:"error,omitempty"`
}

type Event struct {
	Event string `json:"event"`
	Data  any    `json:"data,omitempty"`
}

// Error codes clients can match on.
const (
	CodeVersion  = "version_mismatch"
	CodeMethod   = "unknown_method"
	CodeBadInput = "bad_request"
	CodeFailed   = "failed"
)

type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

// Errorf builds an *Error; handlers return it to choose the code.
func Errorf(code, format string, a ...any) *Error {
	return &Error{Code: code, Message: fmt.Sprintf(format, a...)}
}

// Handler serves one method. Returning a non-*Error error reports CodeFailed.
type Handler func(params json.RawMessage) (any, error)

// DefaultSocketPath is $XDG_RUNTIME_DIR/ano/anod.sock.
func DefaultSocketPath() string {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = fmt.Sprintf("/run/user/%d", os.Getuid())
	}
	return filepath.Join(dir, "ano", "anod.sock")
}

// ErrRunning: another anod holds the lock for this socket.
var ErrRunning = errors.New("anod is already running")

type Server struct {
	path     string
	lock     *os.File
	handlers map[string]Handler
	mu       sync.Mutex
	conns    map[*conn]struct{}
	ln       net.Listener
}

type conn struct {
	c      net.Conn
	wmu    sync.Mutex
	subAll bool
	subs   map[string]bool
}

func (c *conn) send(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	c.wmu.Lock()
	defer c.wmu.Unlock()
	c.c.SetWriteDeadline(time.Now().Add(2 * time.Second)) // a stuck reader must not stall broadcasts
	_, err = c.c.Write(append(b, '\n'))
	return err
}

func NewServer(path string) *Server {
	return &Server{path: path, handlers: map[string]Handler{}, conns: map[*conn]struct{}{}}
}

// Handle registers a method. Call before Listen.
func (s *Server) Handle(method string, h Handler) { s.handlers[method] = h }

// Listen prepares the private directory, takes the instance lock (returns
// ErrRunning if another anod holds it), clears a stale socket and binds with
// mode 0600. The lock is an flock, so it can't go stale: it dies with the process.
func (s *Server) Listen() error {
	if len(s.path) >= 108 { // sockaddr_un.sun_path
		return fmt.Errorf("socket path is %d bytes, over the 107-byte Unix limit: %s", len(s.path), s.path)
	}
	if err := ensurePrivateDir(filepath.Dir(s.path)); err != nil {
		return err
	}
	lock, err := os.OpenFile(s.path+".lock", os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return err
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		lock.Close()
		return fmt.Errorf("%w (%s)", ErrRunning, s.path)
	}
	s.lock = lock
	if err := os.Remove(s.path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	old := syscall.Umask(0o177) // socket is born 0600, no window with wider perms
	ln, err := net.Listen("unix", s.path)
	syscall.Umask(old)
	if err != nil {
		return err
	}
	s.ln = ln
	return os.Chmod(s.path, 0o600)
}

// ensurePrivateDir creates dir as 0700, or tightens an existing one we own.
func ensurePrivateDir(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	fi, err := os.Lstat(dir)
	if err != nil {
		return err
	}
	st, ok := fi.Sys().(*syscall.Stat_t)
	if !fi.IsDir() || !ok || int(st.Uid) != os.Getuid() {
		return fmt.Errorf("%s is not a directory owned by uid %d", dir, os.Getuid())
	}
	if fi.Mode().Perm() != 0o700 {
		return os.Chmod(dir, 0o700)
	}
	return nil
}

// Serve accepts until ctx is cancelled, then closes the listener and removes the socket.
func (s *Server) Serve(ctx context.Context) error {
	go func() {
		<-ctx.Done()
		s.ln.Close()
		s.mu.Lock()
		for c := range s.conns {
			c.c.Close()
		}
		s.mu.Unlock()
	}()
	defer s.lock.Close() // runs last: the socket is gone before the lock is released
	defer os.Remove(s.path)
	for {
		nc, err := s.ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		c := &conn{c: nc, subs: map[string]bool{}}
		s.mu.Lock()
		s.conns[c] = struct{}{}
		s.mu.Unlock()
		go s.serveConn(c)
	}
}

// Clients returns the number of open connections.
func (s *Server) Clients() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.conns)
}

func (s *Server) serveConn(c *conn) {
	defer func() {
		s.mu.Lock()
		delete(s.conns, c)
		s.mu.Unlock()
		c.c.Close()
	}()
	sc := bufio.NewScanner(c.c)
	sc.Buffer(make([]byte, 0, 4096), 1<<20)
	for sc.Scan() {
		if len(sc.Bytes()) == 0 {
			continue
		}
		if err := c.send(s.dispatch(c, sc.Bytes())); err != nil {
			return
		}
	}
}

func (s *Server) dispatch(c *conn, line []byte) Response {
	var req Request
	if err := json.Unmarshal(line, &req); err != nil {
		return Response{Error: Errorf(CodeBadInput, "invalid JSON: %v", err)}
	}
	if req.V != version.API {
		return Response{ID: req.ID, Error: Errorf(CodeVersion,
			"anod speaks API v%d, the client sent v%d; update the shell or anod", version.API, req.V)}
	}
	if req.Method == "subscribe" {
		return Response{ID: req.ID, Result: s.subscribe(c, req.Params)}
	}
	h, ok := s.handlers[req.Method]
	if !ok {
		return Response{ID: req.ID, Error: Errorf(CodeMethod, "unknown method %q", req.Method)}
	}
	res, err := h(req.Params)
	if err != nil {
		var e *Error
		if !errors.As(err, &e) {
			e = &Error{Code: CodeFailed, Message: err.Error()}
		}
		return Response{ID: req.ID, Error: e}
	}
	if res == nil {
		res = true // "result" must be present for a success
	}
	return Response{ID: req.ID, Result: res}
}

// subscribe: {"events":["a","b"]} subscribes to those; no params means all.
func (s *Server) subscribe(c *conn, params json.RawMessage) any {
	var p struct {
		Events []string `json:"events"`
	}
	_ = json.Unmarshal(params, &p)
	c.wmu.Lock()
	defer c.wmu.Unlock()
	if len(p.Events) == 0 {
		c.subAll = true
	}
	for _, e := range p.Events {
		c.subs[e] = true
	}
	return map[string]any{"all": c.subAll, "events": p.Events}
}

// Broadcast pushes an event to every subscribed connection.
func (s *Server) Broadcast(name string, data any) {
	s.mu.Lock()
	targets := make([]*conn, 0, len(s.conns))
	for c := range s.conns {
		c.wmu.Lock()
		if c.subAll || c.subs[name] {
			targets = append(targets, c)
		}
		c.wmu.Unlock()
	}
	s.mu.Unlock()
	for _, c := range targets {
		if err := c.send(Event{Event: name, Data: data}); err != nil {
			log.Printf("ipc: drop subscriber: %v", err)
			c.c.Close()
		}
	}
}

// Call is the client side: one request on a fresh connection, events skipped.
func Call(path, method string, params any) (json.RawMessage, error) {
	c, err := net.DialTimeout("unix", path, time.Second)
	if err != nil {
		return nil, err
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(10 * time.Second))
	return roundTrip(c, method, params)
}

func roundTrip(rw io.ReadWriter, method string, params any) (json.RawMessage, error) {
	req := map[string]any{"v": version.API, "id": 1, "method": method}
	if params != nil {
		req["params"] = params
	}
	b, _ := json.Marshal(req)
	if _, err := rw.Write(append(b, '\n')); err != nil {
		return nil, err
	}
	sc := bufio.NewScanner(rw)
	sc.Buffer(make([]byte, 0, 4096), 1<<20)
	for sc.Scan() {
		var r struct {
			Event  string          `json:"event"`
			Result json.RawMessage `json:"result"`
			Error  *Error          `json:"error"`
		}
		if err := json.Unmarshal(sc.Bytes(), &r); err != nil {
			return nil, err
		}
		if r.Event != "" {
			continue
		}
		if r.Error != nil {
			return nil, r.Error
		}
		return r.Result, nil
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return nil, io.ErrUnexpectedEOF
}
