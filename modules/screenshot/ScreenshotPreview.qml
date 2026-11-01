import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The card after a screenshot (services/Screenshot.qml): a thumbnail with
 * Copy, Save, Edit (satty or swappy), Delete and Close. It leaves after
 * screenshot.previewSeconds unless the pointer is on it; screenshot.onTimeout
 * then keeps the temp file, saves it or deletes it. Also shows the countdown
 * of a delayed capture. After text recognition (Screenshot.recognised) the
 * card shows the text instead, copied already, with Add to note and Pin.
 */
Scope {
    id: root
    readonly property var cfg: Config.options?.screenshot ?? {}
    readonly property string edge: cfg.previewEdge ?? "bottomRight"
    readonly property bool onTop: edge.startsWith("top")
    readonly property bool onLeft: edge.endsWith("Left")

    property string file: ""
    property string text: ""          // recognised text: the card shows it instead of a picture
    property bool shown: false
    property string note: ""          // "Saved to …", "Copied", errors

    Connections {
        target: Screenshot
        // Out of the next picture: made transparent at once while the window
        // stays mapped (an unmapping layer can linger in the compositor's
        // own exit animation and end up in the shot).
        function onPreparingChanged() { if (Screenshot.preparing) { root.settlePrevious(); root.close() } }
        function onCaptured(path, mode) {
            root.file = path
            root.text = ""
            root.note = ""
            if (root.cfg.copyOnCapture ?? true) root.copy(false)
            root.shown = true
            dismiss.restart()
        }
        function onRecognised(text, warning) {
            root.file = ""
            root.text = text
            root.note = warning || "Copied"
            root.copyText()
            root.shown = true
            dismiss.restart()
        }
        function onFailed(mode, reason) {
            if (reason !== "cancelled") Quickshell.execDetached(["notify-send", "-a", "AnoShell", mode === "ocr" ? "Text recognition" : "Screenshot", reason])
        }
    }

    // Values go in as environment, never into the script text.
    function copy(withNote) {
        Quickshell.execDetached({ command: ["bash", "-c", 'wl-copy -t image/png < "$F"'], environment: ({ F: root.file }) })
        if (withNote) root.note = "Copied"
    }
    function copyText() { Quickshell.execDetached({ command: ["bash", "-c", 'printf "%s" "$T" | wl-copy'], environment: ({ T: root.text }) }) }
    function addToNote() { root.note = Notepad.appendText(root.text) ? "Added to the note" : "Turn on the notepad first (Settings → Sidebars)" }
    function pinText() { Cliphist.pinText(root.text); root.note = "Pinned in the clipboard" }
    function save() { saveProc.exec({ command: ["bash", "-c",
        'P=$(xdg-user-dir PICTURES 2>/dev/null); [ -z "$P" ] || [ "$P" = "$HOME" ] && P="$HOME/Pictures"; D="${SAVE:-$P/Screenshots}"; D="${D/#\\~/$HOME}"; mkdir -p -- "$D" && N="${F##*/}" && N="${N%.*}" && N="${N%.*}.png" && mv -- "$F" "$D/$N" && chmod 644 -- "$D/$N" && printf "%s" "$D/$N"'],
        environment: ({ F: root.file, SAVE: root.cfg.saveDir ?? "" }) }) }
    Process {
        id: saveProc
        stdout: StdioCollector { id: savedTo }
        onExited: code => {
            root.note = code === 0 ? `Saved to ${savedTo.text.replace(Quickshell.env("HOME"), "~")}` : "Couldn't save"
            if (code === 0 && savedTo.text) root.file = savedTo.text // moved: Copy/Edit/Delete act on the saved file now
        }
    }
    function edit() {
        Quickshell.execDetached({ command: ["bash", "-c", 'if command -v satty >/dev/null; then exec satty --filename "$F"; else exec swappy -f "$F"; fi'], environment: ({ F: root.file }) })
        root.close()
    }
    function remove() {
        Quickshell.execDetached(["rm", "-f", "--", root.file])
        root.file = ""
        root.close()
    }
    function close() { dismiss.stop(); root.shown = false }
    // A new shot while this one's card is up: this one still gets its timeout
    // action (onTimeout "save" would otherwise lose it).
    function settlePrevious() {
        if (!dismiss.running || !root.file || root.text) return
        const act = root.cfg.onTimeout ?? "keep"
        if (act === "save") root.save()
        else if (act === "delete") Quickshell.execDetached(["rm", "-f", "--", root.file])
    }

    // Auto-dismiss, paused while the pointer is on the card.
    Timer {
        id: dismiss
        interval: Math.max(1, root.cfg.previewSeconds ?? 6) * 1000
        running: false
        onTriggered: {
            if ((root.cfg.previewSeconds ?? 6) <= 0) return
            if (hover.hovered) { restart(); return }
            const act = root.text ? "keep" : (root.cfg.onTimeout ?? "keep")
            if (act === "save") root.save()
            if (act === "delete") root.remove()
            else root.close()
        }
    }

    PanelWindow {
        id: win
        visible: root.shown || card.opacity > 0.01 || Screenshot.countdown > 0 || Screenshot.preparing
        screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:screenshot"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: root.onTop; bottom: !root.onTop; left: root.onLeft; right: !root.onLeft }
        margins { top: 16; bottom: 16; left: 16; right: 16 }
        implicitWidth: 360
        implicitHeight: 300
        mask: Region { item: Screenshot.countdown > 1 ? countdownPill : card }

        // A delayed capture counts down here (and leaves before the shot).
        Rectangle {
            id: countdownPill
            // Gone for the last second, so it is long off the screen when the shot is taken.
            visible: Screenshot.countdown > 1 && !Screenshot.preparing
            anchors { right: root.onLeft ? undefined : parent.right; left: root.onLeft ? parent.left : undefined
                      top: root.onTop ? parent.top : undefined; bottom: root.onTop ? undefined : parent.bottom }
            implicitWidth: cdRow.implicitWidth + 24; implicitHeight: 40
            radius: 20
            color: Appearance.m3colors.m3surfaceContainer
            RowLayout {
                id: cdRow
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol { text: "timer"; iconSize: 18; color: Appearance.colors.colPrimary }
                StyledText { text: `Screenshot in ${Screenshot.countdown}`; font.weight: Font.DemiBold }
                MaterialSymbol {
                    text: "close"; iconSize: 16
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Screenshot.cancel() }
                }
            }
        }

        SurfaceMaterial {
            id: card
            surface: "screenshot"
            width: 340
            height: col.implicitHeight + 20
            anchors { right: root.onLeft ? undefined : parent.right; left: root.onLeft ? parent.left : undefined
                      top: root.onTop ? parent.top : undefined; bottom: root.onTop ? undefined : parent.bottom }
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            // Slides in from its own side.
            opacity: root.shown && !Screenshot.preparing ? 1 : 0
            transform: Translate {
                x: root.shown ? 0 : (root.onLeft ? -40 : 40)
                Behavior on x { id: slideMotion; MotionSpring { token: Math.abs(slideMotion.targetValue) < 0.5 ? "liquid" : "settle" } }
            }
            Behavior on opacity { id: opacityMotion; enabled: !Screenshot.preparing; NumberAnimation { duration: AnimationConfig.scaledDuration(opacityMotion.targetValue > 0.5 ? 220 : 160); easing.type: Easing.BezierSpline; easing.bezierCurve: opacityMotion.targetValue > 0.5 ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel } }
            HoverHandler { id: hover }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 8
                // Recognised text (selectable; scrolls when long).
                Rectangle {
                    visible: root.text !== ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(180, textView.implicitHeight + 16)
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    clip: true
                    Flickable {
                        anchors.fill: parent; anchors.margins: 8
                        contentHeight: textView.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        TextEdit {
                            id: textView
                            width: parent.width
                            text: root.text
                            readOnly: true; selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            color: Appearance.colors.colOnLayer1
                            selectionColor: Appearance.colors.colPrimary
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
                Rectangle {
                    visible: root.text === ""
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: root.file ? "file://" + root.file : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        sourceSize.width: 640
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.edit() }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.note !== ""
                    text: root.note
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    ToolbarButton { iconName: "content_copy"; iconSize: 18; toolTipText: "Copy"; onClicked: { if (root.text) { root.copyText(); root.note = "Copied" } else root.copy(true) } }
                    ToolbarButton { visible: !root.text; iconName: "save"; iconSize: 18; toolTipText: "Save to Pictures/Screenshots"; onClicked: root.save() }
                    ToolbarButton { visible: !root.text; iconName: "edit"; iconSize: 18; toolTipText: "Edit (satty / swappy)"; onClicked: root.edit() }
                    ToolbarButton { visible: !root.text; iconName: "delete"; iconSize: 18; toolTipText: "Delete"; onClicked: root.remove() }
                    ToolbarButton { visible: !!root.text; iconName: "note_add"; iconSize: 18; toolTipText: "Add to note"; onClicked: root.addToNote() }
                    ToolbarButton { visible: !!root.text; iconName: "push_pin"; iconSize: 18; toolTipText: "Pin"; onClicked: root.pinText() }
                    Item { Layout.fillWidth: true }
                    ToolbarButton { iconName: "close"; iconSize: 18; toolTipText: "Close"; onClicked: root.close() }
                }
            }
        }
    }
}
