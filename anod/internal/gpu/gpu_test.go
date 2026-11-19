package gpu

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func put(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func link(t *testing.T, target, name string) {
	t.Helper()
	os.MkdirAll(filepath.Dir(name), 0o755)
	if err := os.Symlink(target, name); err != nil {
		t.Fatal(err)
	}
}

// A hybrid laptop: Intel i915 card0 and an AMD card1 with 8 GiB.
func fakeMachine(t *testing.T) (*Sampler, string) {
	sys, proc := t.TempDir(), t.TempDir()
	devI, devA := filepath.Join(sys, "devices/pci0000:00/0000:00:02.0"), filepath.Join(sys, "devices/pci0000:00/0000:03:00.0")
	put(t, devI, "vendor", "0x8086\n")
	put(t, devI, "device", "0x46a8\n")
	link(t, "../../bus/pci/drivers/i915", filepath.Join(devI, "driver"))
	put(t, devA, "vendor", "0x1002\n")
	put(t, devA, "device", "0x73df\n")
	link(t, "../../bus/pci/drivers/amdgpu", filepath.Join(devA, "driver"))
	put(t, devA, "mem_info_vram_total", "8589934592\n")
	put(t, devA, "mem_info_vram_used", "1073741824\n")
	put(t, devA, "gpu_busy_percent", "37\n")
	put(t, devA, "pp_dpm_sclk", "0: 500Mhz\n1: 1800Mhz *\n2: 2600Mhz\n")
	put(t, devA, "hwmon/hwmon5/temp1_input", "61000\n")
	link(t, devI, filepath.Join(sys, "class/drm/card0/device"))
	link(t, devA, filepath.Join(sys, "class/drm/card1/device"))
	os.MkdirAll(filepath.Join(sys, "class/drm/card0-eDP-1"), 0o755) // a connector, not a card
	put(t, sys, "class/drm/card0/gt_act_freq_mhz", "900\n")
	put(t, sys, "class/drm/card0/gt_min_freq_mhz", "100\n")
	put(t, sys, "class/drm/card0/gt_max_freq_mhz", "1250\n")
	ids := filepath.Join(t.TempDir(), "pci.ids")
	put(t, filepath.Dir(ids), "pci.ids", "1002  Advanced Micro Devices, Inc. [AMD/ATI]\n\t73df  Navi 22 [Radeon RX 6700 XT]\n8086  Intel Corporation\n\t46a8  Alder Lake-UP3 GT2 [Iris Xe Graphics]\n\t\t1234 5678  a subsystem\n")
	return &Sampler{Sys: sys, Proc: proc, PCIIDs: ids}, proc
}

// A process with two fds on the same DRM client (counted once).
func i915Client(t *testing.T, proc, pid, id string, render, video string) {
	info := "drm-driver:\ti915\ndrm-client-id:\t" + id + "\ndrm-pdev:\t0000:00:02.0\ndrm-engine-render:\t" + render + " ns\ndrm-engine-video:\t" + video + " ns\ndrm-engine-capacity-video:\t2\n"
	for _, fd := range []string{"7", "9"} {
		put(t, proc, pid+"/fdinfo/"+fd, info)
		if _, err := os.Lstat(filepath.Join(proc, pid, "fd", fd)); err != nil {
			link(t, "/dev/dri/renderD128", filepath.Join(proc, pid, "fd", fd))
		}
	}
}

func TestCardsAndChoice(t *testing.T) {
	s, _ := fakeMachine(t)
	cards := s.Cards(time.Unix(1, 0))
	if len(cards) != 2 {
		t.Fatalf("connectors aren't cards: %+v", cards)
	}
	i, a := cards[0], cards[1]
	if i.Name != "Alder Lake-UP3 GT2 [Iris Xe Graphics]" || i.Driver != "i915" || !i.Integrated || i.PCI != "0000:00:02.0" {
		t.Fatalf("intel: %+v", i)
	}
	if a.Name != "Navi 22 [Radeon RX 6700 XT]" || a.Integrated || !a.Shown || i.Shown {
		t.Fatalf("the discrete AMD card is shown: %+v / %+v", a, i)
	}
	s.Want = func() string { return "card0" }
	if c := s.Cards(time.Unix(2, 0)); !c[0].Shown || c[1].Shown {
		t.Fatalf("vitals.gpu_card wins: %+v", c)
	}
}

func TestAMDAndIntelLoad(t *testing.T) {
	s, proc := fakeMachine(t)
	s.Want = func() string { return "card0" } // Intel shown: its load is read
	i915Client(t, proc, "100", "33", "1000000000", "0")
	i915Client(t, proc, "200", "34", "0", "0")
	t0 := time.Unix(100, 0)
	g := s.Read(t0, time.Second)
	if g[0].Load != nil {
		t.Fatal("first Intel sample has no load yet")
	}
	if a := g[1]; *a.Load != 37 || *a.MHz != 1800 || *a.MinMHz != 500 || *a.MaxMHz != 2600 || *a.MemUsed != 1<<30 || *a.Temp != 61 {
		t.Fatalf("amd: %+v", a)
	}
	if *g[0].MHz != 900 || *g[0].MaxMHz != 1250 || g[0].MemTotal != nil || g[0].Temp != nil {
		t.Fatalf("intel clocks / no memory: %+v", g[0])
	}
	// 1 s later: client 33 rendered 250 ms; client 34 decoded 1 s on one of two video engines.
	i915Client(t, proc, "100", "33", "1250000000", "0")
	i915Client(t, proc, "200", "34", "0", "1000000000")
	g = s.Read(t0.Add(time.Second), time.Second)
	if g[0].Load == nil || *g[0].Load != 50 {
		t.Fatalf("busiest class: video 1 s of 2 engines = 50%%, got %v", g[0].Load)
	}
	// A new client appears: it counts from its next sample, not its whole life.
	i915Client(t, proc, "300", "35", "900000000000", "0")
	s.fdsAt = time.Time{} // the 10 s scan of new processes
	if g = s.Read(t0.Add(2*time.Second), time.Second); *g[0].Load != 0 {
		t.Fatalf("a new client must not spike the load: %v", *g[0].Load)
	}
}

func TestXeCycles(t *testing.T) {
	prev := engineTimes{"5": {"rcs": {cycles: 100, total: 1000, capacity: 1}}}
	now := engineTimes{"5": {"rcs": {cycles: 400, total: 2000, capacity: 1}}}
	if l, ok := busy(prev, now, time.Second); !ok || l != 30 {
		t.Fatalf("xe: 300 of 1000 cycles = 30%%, got %v", l)
	}
	if _, ok := busy(prev, now, time.Minute); ok {
		t.Fatal("a gap after a pause gives no load")
	}
	_, id, e := parseFdinfo([]byte("drm-client-id: 5\ndrm-cycles-rcs: 400\ndrm-total-cycles-rcs: 2000\ndrm-engine-capacity-ccs: 4\n"))
	if id != "5" || e["rcs"].cycles != 400 || e["rcs"].total != 2000 || e["ccs"].capacity != 4 {
		t.Fatalf("parse xe: %q %+v", id, e)
	}
}

func TestNvidia(t *testing.T) {
	pci, r, ok := parseNvLine("00000000:01:00.0, 37, 1024, 8192, 54, 1410, [N/A]")
	if !ok || pci != "0000:01:00.0" || *r.load != 37 || *r.memTotal != 8192 || *r.temp != 54 || r.maxMHz != nil {
		t.Fatalf("nvidia line: %s %+v", pci, r)
	}
	s := &Sampler{LookPath: func(string) (string, error) { return "", errors.New("no") }}
	g := GPU{Vendor: "NVIDIA", PCI: "0000:01:00.0"}
	s.readNvidia(&g, time.Second)
	if g.Note != "no figures (install nvidia-utils)" || g.Load != nil {
		t.Fatalf("without nvidia-smi: %+v", g)
	}
}
