package events

import (
	"context"
	"errors"
	"os"

	"github.com/godbus/dbus/v5"
)

// watch subscribes conn to rules and hands each signal to on until ctx ends
// or the bus goes away (an error, so the shell is told).
func watch(ctx context.Context, conn *dbus.Conn, ready func(), on func(*dbus.Signal), rules ...[]dbus.MatchOption) error {
	for _, r := range rules {
		if err := conn.AddMatchSignal(r...); err != nil {
			return err
		}
	}
	ch := make(chan *dbus.Signal, 64)
	conn.Signal(ch)
	ready()
	for {
		select {
		case <-ctx.Done():
			return nil
		case sig, ok := <-ch:
			if !ok || sig == nil {
				return errors.New("bus connection closed")
			}
			on(sig)
		}
	}
}

const nmName = "org.freedesktop.NetworkManager"

// NetworkManager pushes "nm" events: {kind: "device", iface} when a device
// changes state, "profile" when a connection profile is added, changed or
// removed, "primary" when the primary connection changes, "active" when an
// active connection (a VPN coming up) changes state. The shell classifies them
// as it did nmcli monitor's lines.
func NetworkManager(ctx context.Context, push Push, ready func()) error {
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return err
	}
	defer conn.Close()
	ifaces := map[dbus.ObjectPath]string{}
	iface := func(p dbus.ObjectPath) string {
		if n, ok := ifaces[p]; ok {
			return n
		}
		v, err := conn.Object(nmName, p).GetProperty(nmName + ".Device.Interface")
		n, _ := v.Value().(string)
		if err == nil {
			ifaces[p] = n
		}
		return n
	}
	return watch(ctx, conn, ready, func(s *dbus.Signal) {
		switch s.Name {
		case nmName + ".Device.StateChanged":
			push("nm", map[string]string{"kind": "device", "iface": iface(s.Path)})
		case nmName + ".Settings.NewConnection", nmName + ".Settings.ConnectionRemoved", nmName + ".Settings.Connection.Updated":
			push("nm", map[string]string{"kind": "profile"})
		case nmName + ".Connection.Active.StateChanged":
			push("nm", map[string]string{"kind": "active"})
		case "org.freedesktop.DBus.Properties.PropertiesChanged":
			if s.Path != "/org/freedesktop/NetworkManager" || len(s.Body) < 2 {
				return
			}
			if changed, ok := s.Body[1].(map[string]dbus.Variant); ok {
				if _, ok := changed["PrimaryConnection"]; ok {
					push("nm", map[string]string{"kind": "primary"})
				}
			}
		}
	}, []dbus.MatchOption{dbus.WithMatchSender(nmName)})
}

// Logind pushes "logind" events for this session: {what: "lock"} and
// "unlock" (loginctl lock-session, idle managers), and "sleep"/"wake".
func Logind(ctx context.Context, push Push, ready func()) error {
	conn, err := dbus.ConnectSystemBus()
	if err != nil {
		return err
	}
	defer conn.Close()
	mgr := conn.Object("org.freedesktop.login1", "/org/freedesktop/login1")
	var session dbus.ObjectPath
	if id := os.Getenv("XDG_SESSION_ID"); id != "" {
		err = mgr.Call("org.freedesktop.login1.Manager.GetSession", 0, id).Store(&session)
	} else {
		err = mgr.Call("org.freedesktop.login1.Manager.GetSessionByPID", 0, uint32(os.Getpid())).Store(&session)
	}
	if err != nil {
		return err // no session: the shell keeps its own watcher
	}
	return watch(ctx, conn, ready, func(s *dbus.Signal) {
		switch {
		case s.Name == "org.freedesktop.login1.Session.Lock" && s.Path == session:
			push("logind", map[string]string{"what": "lock"})
		case s.Name == "org.freedesktop.login1.Session.Unlock" && s.Path == session:
			push("logind", map[string]string{"what": "unlock"})
		case s.Name == "org.freedesktop.login1.Manager.PrepareForSleep" && len(s.Body) > 0:
			if b, _ := s.Body[0].(bool); b {
				push("logind", map[string]string{"what": "sleep"})
			} else {
				push("logind", map[string]string{"what": "wake"})
			}
		}
	},
		[]dbus.MatchOption{dbus.WithMatchSender("org.freedesktop.login1"), dbus.WithMatchObjectPath(session), dbus.WithMatchInterface("org.freedesktop.login1.Session")},
		[]dbus.MatchOption{dbus.WithMatchSender("org.freedesktop.login1"), dbus.WithMatchMember("PrepareForSleep")})
}

const gameMode = "com.feralinteractive.GameMode"

// GameMode pushes "gamemode" {count}: at start and whenever gamemoded signals
// or comes and goes. Match rules only; ClientCount is read only while the
// name has an owner, since any call to it starts gamemoded.
func GameMode(ctx context.Context, push Push, ready func()) error {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return err
	}
	defer conn.Close()
	count := func() {
		var has bool
		n := int32(0)
		if conn.BusObject().Call("org.freedesktop.DBus.NameHasOwner", 0, gameMode).Store(&has) == nil && has {
			var val dbus.Variant
			if conn.Object(gameMode, "/com/feralinteractive/GameMode").Call("org.freedesktop.DBus.Properties.Get", dbus.FlagNoAutoStart, gameMode, "ClientCount").Store(&val) == nil {
				n, _ = val.Value().(int32)
			}
		}
		push("gamemode", map[string]int32{"count": n})
	}
	return watch(ctx, conn, func() { ready(); count() }, func(*dbus.Signal) { count() },
		[]dbus.MatchOption{dbus.WithMatchSender(gameMode)},
		[]dbus.MatchOption{dbus.WithMatchInterface("org.freedesktop.DBus"), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, gameMode)})
}

const kdeConnect = "org.kde.kdeconnect"

// KdeConnect pushes "kdeconnect" {path, member} for kdeconnectd's signals,
// and {path: "/modules/kdeconnect", member: "owner"} when it starts or stops.
// Match rules only (watching doesn't start it).
func KdeConnect(ctx context.Context, push Push, ready func()) error {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return err
	}
	defer conn.Close()
	return watch(ctx, conn, ready, func(s *dbus.Signal) {
		if s.Name == "org.freedesktop.DBus.NameOwnerChanged" {
			push("kdeconnect", map[string]string{"path": "/modules/kdeconnect", "member": "owner"})
			return
		}
		push("kdeconnect", map[string]string{"path": string(s.Path), "member": s.Name})
	},
		[]dbus.MatchOption{dbus.WithMatchSender(kdeConnect)},
		[]dbus.MatchOption{dbus.WithMatchInterface("org.freedesktop.DBus"), dbus.WithMatchMember("NameOwnerChanged"), dbus.WithMatchArg(0, kdeConnect)})
}
