package stats

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func write(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func fakeMachine(t *testing.T, stat, netdev string) (string, string) {
	proc, sys := t.TempDir(), t.TempDir()
	write(t, proc, "stat", stat)
	write(t, proc, "meminfo", "MemTotal:       16000000 kB\nMemFree:  1 kB\nMemAvailable:    4000000 kB\nSwapTotal: 2000000 kB\nSwapFree: 1500000 kB\n")
	write(t, proc, "net/dev", netdev)
	write(t, sys, "devices/system/cpu/cpu0/cpufreq/scaling_cur_freq", "2000000\n")
	write(t, sys, "devices/system/cpu/cpu1/cpufreq/scaling_cur_freq", "3000000\n")
	write(t, sys, "devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq", "400000\n")
	write(t, sys, "devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq", "4800000\n")
	write(t, sys, "class/thermal/thermal_zone0/type", "acpitz\n")
	write(t, sys, "class/thermal/thermal_zone0/temp", "40000\n")
	write(t, sys, "class/thermal/thermal_zone1/type", "x86_pkg_temp\n")
	write(t, sys, "class/thermal/thermal_zone1/temp", "55500\n")
	return proc, sys
}

const netA = `Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 999999 0 0 0 0 0 0 0 999999 0 0 0 0 0 0 0
wlan0: 1000 0 0 0 0 0 0 0 500 0 0 0 0 0 0 0
  tun0: 777777 0 0 0 0 0 0 0 777777 0 0 0 0 0 0 0
`

func TestReaderRates(t *testing.T) {
	stat1 := "cpu  100 0 100 800 0 0 0 0\ncpu0 50 0 50 400 0 0 0\ncpu1 50 0 50 400 0 0 0\nintr 1\n"
	proc, sys := fakeMachine(t, stat1, netA)
	r := &Reader{Proc: proc, Sys: sys}
	t0 := time.Unix(1000, 0)
	s := r.Read(t0)
	if s.CPU.Total != nil || s.Net.Rx != nil {
		t.Fatalf("first sample must have pending rates: %+v %+v", s.CPU, s.Net)
	}
	if s.CPU.Count != 2 || s.CPU.MHz != 2500 || s.CPU.MinMHz != 400 || s.CPU.MaxMHz != 4800 {
		t.Fatalf("cpu = %+v", s.CPU)
	}
	if s.Mem.TotalKB != 16000000 || s.Mem.AvailKB != 4000000 || s.Mem.SwapFreeKB != 1500000 {
		t.Fatalf("mem = %+v", s.Mem)
	}
	if s.Temp.C == nil || *s.Temp.C != 55.5 || s.Temp.Sensor != "x86_pkg_temp" {
		t.Fatalf("temp = %+v", s.Temp)
	}
	if s.Net.Links != 1 || s.Net.RxBytes != 1000 {
		t.Fatalf("lo and tun0 must be left out: %+v", s.Net)
	}
	// 2 s later: cpu0 fully busy, cpu1 idle; wlan0 got 4000 bytes in, 1000 out.
	write(t, proc, "stat", "cpu  300 0 100 1000 0 0 0 0\ncpu0 250 0 50 400 0 0 0\ncpu1 50 0 50 600 0 0 0\n")
	write(t, proc, "net/dev", `x
y
wlan0: 5000 0 0 0 0 0 0 0 1500 0 0 0 0 0 0 0
`)
	s = r.Read(t0.Add(2 * time.Second))
	if s.CPU.Total == nil || *s.CPU.Total != 0.5 || s.CPU.Cores[0] != 1 || s.CPU.Cores[1] != 0 {
		t.Fatalf("cpu rates = %v %v", s.CPU.Total, s.CPU.Cores)
	}
	if s.Net.Rx == nil || *s.Net.Rx != 2000 || *s.Net.Tx != 500 {
		t.Fatalf("net rates = %v %v", s.Net.Rx, s.Net.Tx)
	}
	// A link that left: counters go backwards, no rate.
	write(t, proc, "net/dev", "x\ny\n")
	if s = r.Read(t0.Add(4 * time.Second)); s.Net.Rx != nil {
		t.Fatalf("backwards counters must give no rate, got %v", *s.Net.Rx)
	}
	if len(s.Disks) != 1 || s.Disks[0].Mount != "/" || s.Disks[0].Size == 0 {
		t.Fatalf("disks = %+v", s.Disks)
	}
}

func TestSensorChoice(t *testing.T) {
	proc, sys := fakeMachine(t, "cpu 1 1 1 1 1 1 1\n", netA)
	write(t, sys, "class/hwmon/hwmon3/name", "k10temp\n")
	write(t, sys, "class/hwmon/hwmon3/temp1_input", "61000\n")
	write(t, sys, "class/hwmon/hwmon3/temp1_label", "Tctl\n")
	write(t, sys, "class/hwmon/hwmon4/name", "nvme\n")
	write(t, sys, "class/hwmon/hwmon4/temp1_input", "33000\n")
	r := &Reader{Proc: proc, Sys: sys}
	if s := r.Read(time.Unix(1, 0)); *s.Temp.C != 61 || s.Temp.Sensor != "k10temp/Tctl" {
		t.Fatalf("vendor package sensor first: %+v", s.Temp)
	}
	r = &Reader{Proc: proc, Sys: sys, Sensor: func() string { return "hwmon4" }}
	if s := r.Read(time.Unix(1, 0)); *s.Temp.C != 33 {
		t.Fatalf("configured sensor wins: %+v", s.Temp)
	}
}

func TestHubLeases(t *testing.T) {
	proc, sys := fakeMachine(t, "cpu 1 1 1 1 1 1 1\n", netA)
	got := make(chan Sample, 64)
	h := NewHub(&Reader{Proc: proc, Sys: sys}, func(s Sample) { got <- s })
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.Run(ctx)

	select {
	case <-got:
		t.Fatal("no lease: no sample")
	case <-time.After(300 * time.Millisecond):
	}
	a := h.Watch(1, 2000, false)
	if s := <-got; s.Interval != 2000 {
		t.Fatalf("first sample at once, interval 2000, got %d", s.Interval)
	}
	h.Watch(2, 100, true) // clamped to 500
	if !h.WantsGPU() {
		t.Fatal("a lease wants the GPU")
	}
	select {
	case s := <-got:
		if s.Interval != 500 {
			t.Fatalf("shorter lease: 500 ms, got %d", s.Interval)
		}
	case <-time.After(1200 * time.Millisecond):
		t.Fatal("the shorter interval must apply at once")
	}
	h.Drop(2)
	h.Unwatch(a)
	time.Sleep(600 * time.Millisecond)
	for len(got) > 0 {
		<-got
	}
	select {
	case <-got:
		t.Fatal("all leases gone: sampling must stop")
	case <-time.After(1200 * time.Millisecond):
	}
}
