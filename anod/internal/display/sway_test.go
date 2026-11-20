package display

import (
	"strings"
	"testing"
)

func TestSway(t *testing.T) {
	var sent []string
	s := Sway{Run: func(args ...string) ([]byte, error) {
		if len(args) > 1 && args[1] == "-t" {
			return []byte(`[{"name":"eDP-1","make":"BOE","model":"X","serial":"1","active":true,"scale":1.5,"transform":"90",
				"rect":{"x":0,"y":0},"current_mode":{"width":1920,"height":1200,"refresh":59950},
				"modes":[{"width":1920,"height":1200,"refresh":59950}],"adaptive_sync_status":"disabled"}]`), nil
		}
		sent = append(sent, strings.Join(args, " "))
		return nil, nil
	}}
	outs, err := s.Current()
	if err != nil || len(outs) != 1 {
		t.Fatal(outs, err)
	}
	o := outs[0]
	if o.Width != 1920 || o.Refresh != 59.95 || o.Scale != 1.5 || o.Transform != 1 || !o.Enabled || o.Modes[0] != "1920x1200@59.950" {
		t.Fatalf("%+v", o)
	}
	if err := s.Apply(outs); err != nil || len(sent) != 1 ||
		sent[0] != "output eDP-1 enable mode 1920x1200@59.950Hz scale 1.5 transform 90 position 0 0 adaptive_sync off" {
		t.Fatalf("%q %v", sent, err)
	}
	sent = nil
	if err := s.Apply([]Output{{Name: "HEADLESS-1", Enabled: true, Width: 1280, Height: 800, Scale: 1}}); err != nil || !strings.Contains(sent[0], "mode 1280x800 scale") {
		t.Fatalf("refresh 0: %q %v", sent, err)
	}
	if err := s.Apply([]Output{{Name: "x; exec rm -rf ~", Enabled: true, Width: 1, Height: 1, Refresh: 60, Scale: 1}}); err == nil {
		t.Fatal("bad name accepted")
	}
}
