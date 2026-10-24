import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * Network detail expansion — bandwidth (rx/tx) + VPN status.
 *
 * Bandwidth row only renders when Config.options.network.usage.enable is
 * true (NetworkUsage service is otherwise dormant). VPN row renders when
 * Config.options.vpn.enable is true and at least one provider is
 * configured. The whole panel hides itself when neither has anything to
 * show, so the sidebar doesn't gain an empty card on default configs.
 */
Rectangle {
    id: root

    readonly property bool showBandwidth: Config.options?.network?.usage?.enable ?? false
    readonly property bool showVpn: (Config.options?.vpn?.enable ?? true)
                                    && (Config.options?.vpn?.providers?.length ?? 0) > 0
    readonly property bool hasContent: showBandwidth || showVpn

    visible: hasContent
    implicitHeight: hasContent ? (col.implicitHeight + 20) : 0
    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 10 }
        spacing: 10

        StyledText {
            text: "Network"
            font.pixelSize: Appearance?.font.pixelSize.small ?? 14
            font.weight: Font.DemiBold
            color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
        }

        // ── Bandwidth ─────────────────────────────────────────────────
        Loader {
            Layout.fillWidth: true
            active: root.showBandwidth
            visible: active
            sourceComponent: RowLayout {
                spacing: 12

                // Download
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            text: "download"; iconSize: 16
                            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                        }
                        StyledText {
                            text: "Down"
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                        }
                    }
                    StyledText {
                        readonly property var fmt: NetworkUsage.formatBytes(NetworkUsage.downloadSpeed)
                        text: `${fmt.value < 10 ? fmt.value.toFixed(1) : Math.round(fmt.value)} ${fmt.unit}`
                        font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
                        font.weight: Font.DemiBold
                        font.family: Appearance?.font.family.numbers
                        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                    }
                    StyledText {
                        readonly property var tot: NetworkUsage.formatBytesTotal(NetworkUsage.downloadTotal)
                        text: `Total ${tot.value < 10 ? tot.value.toFixed(1) : Math.round(tot.value)} ${tot.unit}`
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: Appearance?.colors.colOutlineVariant ?? "#49454F"
                    opacity: 0.4
                }

                // Upload
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            text: "upload"; iconSize: 16
                            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                        }
                        StyledText {
                            text: "Up"
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                        }
                    }
                    StyledText {
                        readonly property var fmt: NetworkUsage.formatBytes(NetworkUsage.uploadSpeed)
                        text: `${fmt.value < 10 ? fmt.value.toFixed(1) : Math.round(fmt.value)} ${fmt.unit}`
                        font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
                        font.weight: Font.DemiBold
                        font.family: Appearance?.font.family.numbers
                        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                    }
                    StyledText {
                        readonly property var tot: NetworkUsage.formatBytesTotal(NetworkUsage.uploadTotal)
                        text: `Total ${tot.value < 10 ? tot.value.toFixed(1) : Math.round(tot.value)} ${tot.unit}`
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                    }
                }
            }
        }

        // ── VPN ───────────────────────────────────────────────────────
        Loader {
            Layout.fillWidth: true
            active: root.showVpn
            visible: active
            sourceComponent: RowLayout {
                spacing: 8

                MaterialSymbol {
                    text: VPN.connected ? "vpn_lock" : (VPN.connecting ? "vpn_key" : "vpn_key_off")
                    iconSize: 22
                    color: VPN.connected
                        ? (Appearance?.colors.colPrimary ?? "#65558F")
                        : (Appearance?.colors.colSubtext ?? "#CAC4D0")
                    fill: VPN.connected ? 1 : 0
                }

                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    StyledText {
                        text: (VPN.currentConfig?.displayName) || VPN.providerName || "VPN"
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        font.weight: Font.DemiBold
                        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    StyledText {
                        text: VPN.connecting
                            ? "Connecting…"
                            : VPN.connected
                                ? "Connected"
                                : (VPN.status?.state === "needs-auth"
                                    ? "Sign-in required"
                                    : (VPN.status?.reason || "Disconnected"))
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                // Toggle button
                Rectangle {
                    implicitWidth: toggleRow.implicitWidth + 16
                    implicitHeight: 32
                    radius: height / 2
                    color: VPN.connected
                        ? Qt.rgba((Appearance?.colors.colPrimary?.r ?? 0.4),
                                  (Appearance?.colors.colPrimary?.g ?? 0.33),
                                  (Appearance?.colors.colPrimary?.b ?? 0.56), 0.2)
                        : Appearance?.colors.colLayer2 ?? "#2B2930"
                    opacity: VPN.connecting ? 0.6 : 1
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }

                    RowLayout {
                        id: toggleRow
                        anchors.centerIn: parent
                        spacing: 4
                        StyledText {
                            text: VPN.connecting
                                ? "…"
                                : VPN.connected ? "Disconnect" : "Connect"
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                            font.weight: Font.DemiBold
                            color: VPN.connected
                                ? (Appearance?.colors.colPrimary ?? "#65558F")
                                : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: VPN.connecting ? Qt.ArrowCursor : Qt.PointingHandCursor
                        enabled: !VPN.connecting
                        onClicked: VPN.toggle()
                    }
                }
            }
        }

        // ── NetBird details: management/signal health, IP, FQDN, peers ──
        Loader {
            Layout.fillWidth: true
            active: root.showVpn && VPN.providerName === "netbird" && !!VPN.status?.netbird
            visible: active
            // Fast polling only while the sidebar is actually open (it stays
            // loaded but hidden when closed, which doesn't change `visible`).
            readonly property bool watching: active && GlobalStates.sidebarRightOpen
            onWatchingChanged: VPN.watch(watching)
            Component.onCompleted: if (watching) VPN.watch(true)
            Component.onDestruction: if (watching) VPN.watch(false)
            sourceComponent: ColumnLayout {
              readonly property var nb: VPN.status.netbird
              spacing: 8
              GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 10
                rowSpacing: 2
                Repeater {
                    model: [
                        { label: "Management", value: nb.management.host || nb.management.url, ok: nb.management.connected, err: nb.management.error },
                        { label: "Signal", value: nb.signal.host || nb.signal.url, ok: nb.signal.connected, err: nb.signal.error },
                        { label: "IP", value: nb.ip, copy: true },
                        { label: "FQDN", value: nb.fqdn, copy: true }
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            Layout.preferredWidth: 86
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        MaterialSymbol {
                            visible: modelData.ok !== undefined
                            text: modelData.ok ? "check_circle" : "error"
                            iconSize: 14
                            color: modelData.ok ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: modelData.ok === false && modelData.err ? modelData.err : (modelData.value || "—")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: modelData.copy ? Appearance.font.family.mono : Appearance.font.family.main
                        }
                        ToolbarButton {
                            visible: !!modelData.copy && !!modelData.value
                            iconName: "content_copy"; iconSize: 14
                            toolTipText: `Copy ${modelData.label}`
                            onClicked: Quickshell.clipboardText = modelData.value
                        }
                    }
                }
              }

              // Exit node: everything goes through one peer, or none (direct).
              RowLayout {
                Layout.fillWidth: true
                visible: VPN.netbirdExitNodes.length > 0
                spacing: 6
                StyledText {
                    Layout.preferredWidth: 86
                    text: "Exit node"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                ChoiceRow {
                    Layout.fillWidth: true
                    enabled: !VPN.netbirdNetworksBusy
                    opacity: enabled ? 1 : 0.6
                    model: [{ value: "", label: "Direct", icon: "public" }].concat(VPN.netbirdExitNodes.map(n => ({ value: n.id, label: n.id, icon: "vpn_lock" })))
                    current: VPN.netbirdExitNode
                    onChose: value => VPN.setNetBirdExitNode(value)
                }
                MaterialSymbol {
                    visible: VPN.netbirdNetworksBusy
                    text: "progress_activity"; iconSize: 16
                    color: Appearance.colors.colPrimary
                    RotationAnimation on rotation { running: VPN.netbirdNetworksBusy; from: 0; to: 360; duration: AnimationConfig.scaledDuration(900) || 900; loops: Animation.Infinite }
                }
              }

              // Routed networks
              Repeater {
                model: VPN.netbirdNetworks.filter(n => !n.exit)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol { text: "lan"; iconSize: 16; color: modelData.selected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: modelData.id; font.pixelSize: Appearance.font.pixelSize.small }
                        StyledText {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: modelData.domains || modelData.network
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.mono
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledSwitch {
                        checked: modelData.selected
                        enabled: !VPN.netbirdNetworksBusy
                        onClicked: VPN.setNetBirdNetwork(modelData.id, checked)
                    }
                }
              }

              // ── Peers: a count that opens into a scrolling list ──
              ColumnLayout {
                id: peersBox
                Layout.fillWidth: true
                spacing: 2
                property bool open: false
                // Rows are updated in place (status refreshes every 2 s while shown).
                ListModel { id: peerRows }
                readonly property var sorted: (nb.peers ?? []).slice().sort((a, b) =>
                    ((b.status === "Connected") - (a.status === "Connected")) || String(a.fqdn).localeCompare(String(b.fqdn)))
                function ago(iso) {
                    const t = Date.parse(iso)
                    if (!isFinite(t) || t < Date.parse("2000-01-01")) return "never"
                    const s = Math.max(0, Math.round((Date.now() - t) / 1000))
                    return s < 60 ? `${s} s ago` : s < 3600 ? `${Math.round(s / 60)} min ago` : s < 86400 ? `${Math.round(s / 3600)} h ago` : `${Math.round(s / 86400)} d ago`
                }
                function row(p) {
                    const on = p.status === "Connected"
                    const ms = Math.round((p.latency ?? 0) / 1e6)
                    const bits = [p.netbirdIp ?? ""]
                    if (on) bits.push(p.connectionType === "P2P" ? "P2P" : "Relayed", `${ms} ms`)
                    bits.push(`handshake ${peersBox.ago(p.lastWireguardHandshake)}`)
                    return { fqdn: String(p.fqdn ?? ""), name: String(p.fqdn ?? "").split(".")[0], ip: String(p.netbirdIp ?? ""), on: on, detail: bits.join(" · ") }
                }
                onSortedChanged: sync()
                Component.onCompleted: sync()
                function sync() {
                    const rows = peersBox.sorted.map(peersBox.row)
                    const same = rows.length === peerRows.count && rows.every((r, i) => peerRows.get(i).fqdn === r.fqdn)
                    if (same) rows.forEach((r, i) => peerRows.set(i, r))
                    else { peerRows.clear(); rows.forEach(r => peerRows.append(r)) }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol { text: "group"; iconSize: 16; color: Appearance.colors.colSubtext }
                    StyledText {
                        Layout.fillWidth: true
                        text: `Peers · ${nb.peersConnected} of ${nb.peersTotal} connected`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    MaterialSymbol {
                        text: "expand_more"; iconSize: 18; color: Appearance.colors.colSubtext
                        rotation: peersBox.open ? 0 : -90
                        Behavior on rotation { Anim {} }
                    }
                    TapHandler { onTapped: peersBox.open = !peersBox.open }
                }
                ListView {
                    id: peerList
                    Layout.fillWidth: true
                    Layout.preferredHeight: peersBox.open ? Math.min(contentHeight, 260) : 0
                    Behavior on Layout.preferredHeight { MotionSpring { token: "settle" } }
                    visible: Layout.preferredHeight > 0.5
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: peerRows
                    spacing: 2
                    delegate: RowLayout {
                        required property string name
                        required property string ip
                        required property bool on
                        required property string detail
                        width: peerList.width
                        spacing: 8
                        Rectangle {
                            implicitWidth: 8; implicitHeight: 8; radius: 4
                            color: on ? Appearance.colors.colSuccess : Appearance.colors.colOutline
                            Behavior on color { CAnim {} }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: name; font.pixelSize: Appearance.font.pixelSize.small }
                            StyledText {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                text: detail
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.mono
                                color: Appearance.colors.colSubtext
                            }
                        }
                        ToolbarButton {
                            iconName: "content_copy"; iconSize: 14
                            toolTipText: `Copy ${ip}`
                            onClicked: Quickshell.clipboardText = ip
                        }
                        ToolbarButton {
                            iconName: "terminal"; iconSize: 14
                            toolTipText: `netbird ssh ${name}`
                            visible: on && /^[0-9.]+$/.test(ip) // offline peers: nothing to SSH into
                            onClicked: DefaultApps.run("terminal", ["-e", "netbird", "ssh", ip]) // NetBird's own SSH (peer keys over the mesh)
                        }
                    }
                }
              }

              StyledText {
                Layout.fillWidth: true
                visible: VPN.netbirdNetworksError !== ""
                text: VPN.netbirdNetworksError
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
              }
            }
        }
    }
}
