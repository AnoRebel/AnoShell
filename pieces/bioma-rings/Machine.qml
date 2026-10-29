// Ported from Bioma (GPL-3.0), services/Machine.qml — only the host name and
// the install date, which is all the growth rings read. An instance per
// organism rather than a singleton, read once when it is created.
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string host: ""

    // When this system was installed, as ms since the epoch; 0 until known.
    // The oldest of the creation of `/` and `/home` and the first line of
    // pacman's log: on btrfs a snapper rollback makes `/` young while `/home`
    // and `/var/log` stay, so no single one is trusted alone.
    property real born: 0

    property FileView hostname: FileView {
        path: "/proc/sys/kernel/hostname"
        onLoaded: root.host = text().trim()
    }

    property Process programs: Process {
        running: true
        command: ["bash", "-c",
            "for p in / /home; do stat -c %W \"$p\" 2>/dev/null; done; "
            + "d=$(head -n1 /var/log/pacman.log 2>/dev/null | sed -n 's/^\\[\\([^]]*\\)\\].*/\\1/p'); "
            + "[ -n \"$d\" ] && date -d \"$d\" +%s 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                const seconds = this.text.split("\n").map(line => parseInt(line, 10))
                                         .filter(value => value > 0);
                if (seconds.length > 0)
                    root.born = Math.min(...seconds) * 1000;
            }
        }
    }
}
