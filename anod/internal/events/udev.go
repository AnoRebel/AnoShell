package events

import (
	"bytes"
	"context"
	"encoding/binary"

	"golang.org/x/sys/unix"
)

// udevKeys are the properties passed on (what DeviceEvents and Drives read).
var udevKeys = []string{"ACTION", "SUBSYSTEM", "DEVTYPE", "DEVNAME", "DEVPATH", "ID_VENDOR", "ID_VENDOR_FROM_DATABASE",
	"ID_MODEL", "ID_MODEL_FROM_DATABASE", "ID_USB_INTERFACES", "ID_FS_LABEL", "ID_BUS"}

// Udev pushes "udev" events for USB devices and block devices, read from
// udevd's netlink group (the messages `udevadm monitor --udev` shows, with
// the hwdb names udev adds). Non-root processes may receive, not send, on
// it, so the messages can only come from udevd.
func Udev(ctx context.Context, push Push, ready func()) error {
	fd, err := unix.Socket(unix.AF_NETLINK, unix.SOCK_RAW|unix.SOCK_CLOEXEC, unix.NETLINK_KOBJECT_UEVENT)
	if err != nil {
		return err
	}
	defer unix.Close(fd)
	if err := unix.Bind(fd, &unix.SockaddrNetlink{Family: unix.AF_NETLINK, Groups: 2}); err != nil {
		return err
	}
	ready()
	buf := make([]byte, 64<<10)
	for ctx.Err() == nil {
		// Poll with a timeout: a blocked recv doesn't wake when the fd is closed.
		n, err := unix.Poll([]unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}, 1000)
		if err == unix.EINTR || n == 0 {
			continue
		}
		if err != nil {
			return err
		}
		m, _, err := unix.Recvfrom(fd, buf, unix.MSG_DONTWAIT)
		if err != nil {
			if err == unix.EAGAIN || err == unix.EINTR || err == unix.ENOBUFS { // ENOBUFS: some were dropped; go on
				continue
			}
			return err
		}
		props, ok := parseUdev(buf[:m])
		if !ok || !wanted(props) {
			continue
		}
		out := map[string]string{}
		for _, k := range udevKeys {
			if v, ok := props[k]; ok {
				out[k] = v
			}
		}
		push("udev", out)
	}
	return nil
}

func wanted(p map[string]string) bool {
	return (p["SUBSYSTEM"] == "usb" && p["DEVTYPE"] == "usb_device") || p["SUBSYSTEM"] == "block"
}

// parseUdev reads a udevd netlink message: "libudev\0", a big-endian magic
// 0xfeedcafe, then host-endian header size, properties offset and length;
// the properties are KEY=VALUE strings, NUL-separated.
func parseUdev(b []byte) (map[string]string, bool) {
	if len(b) < 40 || !bytes.Equal(b[:8], []byte("libudev\x00")) || binary.BigEndian.Uint32(b[8:12]) != 0xfeedcafe {
		return nil, false
	}
	off, n := binary.NativeEndian.Uint32(b[16:20]), binary.NativeEndian.Uint32(b[20:24])
	if uint64(off)+uint64(n) > uint64(len(b)) {
		return nil, false
	}
	props := map[string]string{}
	for _, kv := range bytes.Split(b[off:off+n], []byte{0}) {
		if k, v, ok := bytes.Cut(kv, []byte{'='}); ok {
			props[string(k)] = string(v)
		}
	}
	return props, true
}
