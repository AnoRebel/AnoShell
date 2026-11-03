import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * The built-in lock screen: clock, avatar, password field, Caps Lock warning,
 * and the opt-in notifications, status row and on-screen keyboard. Draws only;
 * the password goes to ctx.submit() (LockContext).
 */
Item {
    id: root
    property var ctx
    // Drawn in Settings' lock preview (LockPreview): the field never takes
    // focus or input, nothing dims.
    property bool miniature: false

    // lock.layout: blocks you moved in Settings (settings-wiring "Interactive
    // previews in Settings"), each { x, y, scale } — its centre as fractions of
    // the screen. A block without an entry stays in the centred column, so no
    // layout looks as it always did.
    readonly property var layout: Config.options?.lock?.layout ?? ({})
    // Where each block is drawn, in this item's coordinates (LockPreview).
    function blockRects() {
        const out = {}
        for (const b of [clockBlock, userBlock, statusBlock, fieldBlock]) {
            const h = b.holder
            if (!h.visible || h.width <= 0) continue
            const o = h.mapToItem(root, 0, 0)
            out[b.key] = { x: o.x, y: o.y, w: h.width * h.scale, h: h.height * h.scale, scale: h.scale }
        }
        return out
    }

    // One movable part of the lock: in the column, or placed on its own.
    component Block: Item {
        id: blk
        required property string key
        required property Item freeLayer
        property var layout: ({})
        property real spacing: 4 // between this block's own lines (the column's was 24)
        default property alias inner: content.data
        property alias holder: content
        readonly property var at: blk.layout?.[blk.key] ?? null
        readonly property bool free: blk.at !== null && Number.isFinite(blk.at.x) && Number.isFinite(blk.at.y)
        readonly property real _scale: Number.isFinite(blk.at?.scale) ? Math.max(0.4, Math.min(3, blk.at.scale)) : 1
        // The centre, kept so the whole block is on this screen (a layout
        // made on another monitor can be bigger than this one allows).
        function _centre(f, size, span) { return Math.max(size / 2, Math.min(span - size / 2, f * span)) }
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: blk.free ? 0 : content.implicitWidth
        implicitHeight: blk.free ? 0 : content.implicitHeight
        ColumnLayout {
            id: content
            parent: blk.free ? blk.freeLayer : blk
            spacing: blk.spacing
            scale: blk.free ? blk._scale : 1
            x: blk.free ? blk._centre(blk.at.x, width * scale, blk.freeLayer.width) - width / 2 : (blk.width - width) / 2
            y: blk.free ? blk._centre(blk.at.y, height * scale, blk.freeLayer.height) - height / 2 : 0
        }
    }

    // Auto-dim after Config.options.lock.dim.idleMs of no input.
    property bool dimmed: false
    Timer {
        id: dimIdleTimer
        interval: Config.options?.lock?.dim?.idleMs ?? 30000
        running: !root.miniature && (Config.options?.lock?.dim?.enable ?? true)
        repeat: false
        onTriggered: root.dimmed = true
    }
    function _wake() {
        root.dimmed = false
        dimIdleTimer.restart()
    }

    Connections {
        target: root.ctx
        function onFailed() {
            passwordInput.text = ""
            errorShake.start()
        }
    }

    // Background: the wallpaper, darkened.
    Rectangle {
        anchors.fill: parent
        color: Appearance?.m3colors.m3background ?? "#1C1B1F"
        Image {
            anchors.fill: parent
            source: root.ctx?.wallpaper ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    }

    // Idle dim overlay — fades to a configurable opacity after dim.idleMs of
    // no input, back to 0 on any pointer/key event.
    Rectangle {
        anchors.fill: parent
        color: "black"
        z: 1
        opacity: root.dimmed ? (Config.options?.lock?.dim?.opacity ?? 0.6) : 0
        Behavior on opacity {
            NumberAnimation { duration: AnimationConfig.scaledDuration(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
        }
    }

    // Catch-all wake input; accepts nothing, so events reach the field.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        z: 2
        onPositionChanged: root._wake()
    }
    Connections {
        target: passwordInput
        function onTextChanged() { root._wake() }
        function onActiveFocusChanged() { root._wake() }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24; width: 320
        z: 3

        // Notifications while locked (lock.notifications.enable); hides when empty.
        LockNotifications {
            Layout.fillWidth: true
        }

        // Clock
        Block {
            id: clockBlock
            key: "clock"; freeLayer: freeLayer; layout: root.layout
            StyledText {
                text: DateTime.time
                font.pixelSize: 72; font.weight: Font.Bold
                font.family: Appearance?.font.family.numbers ?? "monospace"
                color: "white"; Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: DateTime.collapsedCalendarFormat
                font.pixelSize: Appearance.font.pixelSize.larger; color: "white"; opacity: 0.6
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // Avatar and name
        Block {
            id: userBlock
            key: "user"; freeLayer: freeLayer; layout: root.layout; spacing: 24
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 80; height: 80; radius: 40
            color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
            border.width: 3; border.color: Appearance?.colors.colPrimary ?? "#65558F"
            Image {
                id: avatar
                anchors.centerIn: parent; width: 72; height: 72
                source: root.ctx?.avatar ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask { maskSource: Rectangle { width: 72; height: 72; radius: 36 } }
            }
            MaterialSymbol {
                anchors.centerIn: parent; text: "person"; iconSize: 40
                color: Appearance?.colors.colPrimary ?? "#65558F"
                visible: avatar.status !== Image.Ready
            }
        }

        StyledText {
            text: root.ctx?.user ?? ""
            font.pixelSize: Appearance.font.pixelSize.huge; font.weight: Font.DemiBold
            font.capitalization: Font.Capitalize
            color: "white"; Layout.alignment: Qt.AlignHCenter
        }
        }

        // Status row (lock.statusRow.enable)
        Block {
            id: statusBlock
            key: "status"; freeLayer: freeLayer; layout: root.layout
            LockStatusRow {
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // Password field and what's said about it; widens on focus
        // (lock.passwordInput.expandOnFocus).
        Block {
            id: fieldBlock
            key: "field"; freeLayer: freeLayer; layout: root.layout; spacing: 24
        Rectangle {
            id: field
            Layout.alignment: Qt.AlignHCenter
            readonly property bool expandOnFocus: Config.options?.lock?.passwordInput?.expandOnFocus ?? true
            Layout.preferredWidth: expandOnFocus ? (passwordInput.activeFocus ? 320 : 240) : 320
            implicitHeight: 48; radius: 24
            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
            }
            color: Qt.rgba(1, 1, 1, 0.1)
            border.width: passwordInput.activeFocus ? 2 : 1
            border.color: (root.ctx?.error ?? "").length > 0 ? Appearance.colors.colError : (passwordInput.activeFocus ? Appearance?.colors.colPrimary ?? "#65558F" : "#33ffffff")

            // A wrong password shakes the field (its content, so the layout
            // keeps its place).
            SequentialAnimation {
                id: errorShake
                loops: 3
                NumberAnimation { target: fieldRow; property: "anchors.horizontalCenterOffset"; to: -10; duration: AnimationConfig.scaledDuration(40) }
                NumberAnimation { target: fieldRow; property: "anchors.horizontalCenterOffset"; to: 10; duration: AnimationConfig.scaledDuration(80) }
                NumberAnimation { target: fieldRow; property: "anchors.horizontalCenterOffset"; to: 0; duration: AnimationConfig.scaledDuration(40) }
            }

            RowLayout {
                id: fieldRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                spacing: 8
                MaterialSymbol {
                    text: root.ctx?.busy ? "hourglass_top" : "lock"
                    iconSize: 20; color: "white"; opacity: 0.5
                }
                TextInput {
                    id: passwordInput
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    font.pixelSize: Appearance.font.pixelSize.normal; color: "white"
                    focus: !root.miniature
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: !root.miniature && !(root.ctx?.busy ?? false)
                    onAccepted: root.ctx?.submit(text)
                    Text {
                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                        text: "Password"; color: "white"; opacity: 0.3; font.pixelSize: Appearance.font.pixelSize.normal
                        visible: passwordInput.text.length === 0
                    }
                }
                MaterialSymbol {
                    text: "arrow_forward"; iconSize: 20; color: "white"
                    visible: passwordInput.text.length > 0 && !(root.ctx?.busy ?? false)
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.ctx?.submit(passwordInput.text)
                    }
                }
            }
        }

        // Fingerprint beside the password (the shell runs the scan).
        RowLayout {
            readonly property var fpState: root.ctx?.fingerprint ?? null
            visible: fpState?.available ?? false
            Layout.alignment: Qt.AlignHCenter
            spacing: 6
            MaterialSymbol {
                text: ["max", "error"].includes(parent.fpState?.state) ? "fingerprint_off" : "fingerprint"
                iconSize: 18
                color: parent.fpState?.state === "fail" ? Appearance.colors.colError : "white"
                opacity: parent.fpState?.state === "scanning" ? 0.9 : 0.5
            }
            StyledText {
                text: parent.fpState?.message || (parent.fpState?.state === "scanning" ? "Or touch the fingerprint reader" : "")
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: parent.fpState?.state === "fail" ? Appearance.colors.colError : "white"
                opacity: 0.8
            }
        }

        StyledText {
            text: root.ctx?.error ?? ""
            visible: text.length > 0
            font.pixelSize: Appearance.font.pixelSize.smallie; color: Appearance.colors.colError
            Layout.alignment: Qt.AlignHCenter
        }

        // Caps Lock warning (LockKeys reads it when the lock starts and on
        // each Caps Lock press)
        StyledText {
            text: "Caps Lock is on"
            visible: (root.ctx?.capsLock ?? false) && !(root.ctx?.busy ?? false)
            font.pixelSize: Appearance.font.pixelSize.smallie; color: Appearance.colors.colWarning
            Layout.alignment: Qt.AlignHCenter
        }

        StyledText {
            text: "Checking…"
            visible: root.ctx?.busy ?? false
            font.pixelSize: Appearance.font.pixelSize.smallie; color: "white"; opacity: 0.5
            Layout.alignment: Qt.AlignHCenter
        }
        }

        // On-screen keyboard (lock.osk.enable)
        LockOSK {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            onKey: (text) => { passwordInput.text = passwordInput.text + text; root._wake() }
            onBackspace: { passwordInput.text = passwordInput.text.slice(0, -1); root._wake() }
            onSubmit: root.ctx?.submit(passwordInput.text)
        }
    }

    // Blocks placed on their own (lock.layout) live here, over the column.
    Item {
        id: freeLayer
        anchors.fill: parent
        z: 3
    }
}
