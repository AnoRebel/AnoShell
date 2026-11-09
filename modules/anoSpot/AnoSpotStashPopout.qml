import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."
import "root:services/anoSpotLogic.js" as AnoSpotLogic

/**
 * Popout panel anchored beneath/above the AnoSpot pill that lists items
 * staged in the AnoSpotStash, with action buttons for LocalSend / Open /
 * Copy path / Move / Reveal, plus any user-defined dropTargets rules from
 * Config.options.anoSpot.dropTargets.
 *
 * Below them, the shelf: pins, recent screenshots and clipboard entries
 * (AnoSpotStash.shots, services/Cliphist; ordered by anoSpotLogic.shelf).
 * Click one to copy it, drag it out into another app, pin or unpin it.
 *
 * UI states (footerStack.current):
 *   "actions"    — default toolbar, one button per action
 *   "localsend"  — device discovery + selection list (replaces toolbar
 *                  while a scan is in progress or devices are listed)
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.anoSpotStashOpen
    readonly property string spotPosition: Config.options?.anoSpot?.position ?? "top"
    readonly property bool spotIsVertical: spotPosition === "left" || spotPosition === "right"

    // Auto-close when the stash empties and the shelf has nothing either.
    Connections {
        target: AnoSpotStash
        function onEmptyChanged() {
            if (AnoSpotStash.empty && Cliphist.pins.length === 0 && AnoSpotStash.shots.length === 0
                    && (AnoSpotStash.shelfSize === 0 || Cliphist.entries.length === 0))
                GlobalStates.anoSpotStashOpen = false;
        }
    }
    // Opening it: the clipboard list and the screenshots brought up to date.
    onOpenChanged: if (open) { Cliphist.refresh(); AnoSpotStash.refresh(); AnoSpotStash.pruneShots() }

    // The grids aren't flickable (a press-and-drag on a cell drags it out);
    // the wheel scrolls them.
    component WheelScroll: WheelHandler {
        required property Flickable view
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const v = view, d = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2
            v.contentY = Math.max(v.originY, Math.min(v.originY + v.contentHeight - v.height, v.contentY - d))
        }
    }

    // One shelf item: a pin, a screenshot or a clipboard entry. Click copies
    // it; dragging it out gives other apps the file (text/uri-list) or the
    // text; the corner pin pins or unpins it.
    component ShelfCell: Item {
        id: cell
        required property var modelData
        width: GridView.view.cellWidth - 6
        height: GridView.view.cellHeight - 6

        readonly property string src: modelData.src
        readonly property var info: src === "pin" ? Cliphist.pinInfo(modelData.pin) : src === "clip" ? modelData.info : ({ kind: "image" })
        readonly property string kind: info.kind
        // The picture on disk, when there is one (a clipboard image once decoded).
        readonly property string imageFile: src === "shot" ? modelData.path
            : src === "pin" && kind === "image" ? (modelData.pin.file ?? "")
            : src === "clip" && kind === "image" ? (/^\//.test(Cliphist.preview("img:" + info.id)) ? Cliphist.preview("img:" + info.id) : "") : ""
        // The whole text (`cliphist list` cuts entries short).
        readonly property string text: {
            if (src !== "clip") return info.text ?? ""
            const full = Cliphist.fullTexts[info.id]
            return full !== undefined && full !== "!" ? full : (info.text ?? "")
        }
        Component.onCompleted: {
            if (src !== "clip") return
            if (kind === "image") Cliphist.requestImage(info.id, info.ext)
            else if (info.needsText || /…$/.test(info.text ?? "")) Cliphist.requestText(info.id)
        }

        function copy() {
            if (src === "shot") AnoSpotStash.copyImage(modelData.path)
            else if (src === "pin") Cliphist.copyPin(modelData.pin, false)
            else Cliphist.copy(modelData.line)
            copied.restart()
        }
        function togglePin() {
            if (src === "pin") Cliphist.unpin(modelData.pin)
            else if (src === "shot") Cliphist.pinFile(modelData.path)
            else Cliphist.pin(modelData.line)
        }

        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.mimeData: cell.imageFile ? { "text/uri-list": AnoSpotLogic.fileUri(cell.imageFile) }
            : cell.kind === "files" ? { "text/uri-list": cell.info.files.map(f => f.uri).join("\r\n") }
            : { "text/plain": cell.text }
        Drag.active: shelfDrag.active
        DragHandler { id: shelfDrag; target: null }
        TapHandler { onTapped: cell.copy() }
        HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
        Timer { id: copied; interval: 900 }

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: cellHover.hovered ? (Appearance?.colors?.colLayer2 ?? "#3a3845") : (Appearance?.colors?.colLayer1 ?? "#2b2930")
            border.width: 1
            border.color: Appearance?.colors?.colOutlineVariant ?? "#44444466"
            clip: true

            Image {
                id: shelfThumb
                anchors.fill: parent
                anchors.margins: 1
                visible: cell.imageFile !== "" && status === Image.Ready
                source: cell.imageFile ? AnoSpotLogic.fileUri(cell.imageFile) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 180
                sourceSize.height: 180
            }
            // Text, a colour, files: a few lines of it, or an icon.
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                visible: !shelfThumb.visible
                spacing: 2
                Rectangle {
                    visible: cell.kind === "color"
                    Layout.alignment: Qt.AlignHCenter
                    width: 28; height: 28; radius: 14
                    color: cell.kind === "color" ? cell.info.color : "transparent"
                }
                MaterialSymbol {
                    visible: cell.kind === "files" || cell.kind === "image"
                    Layout.alignment: Qt.AlignHCenter
                    text: cell.kind === "files" ? "draft" : "image"
                    iconSize: 24
                    color: Appearance?.colors?.colOnLayer0Subtle ?? "#a6adc8"
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: cell.kind === "files" ? cell.info.files.map(f => f.name).join("\n") : cell.kind === "image" ? "" : cell.text
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    maximumLineCount: cell.kind === "text" ? 4 : 2
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                }
            }
            // Copied.
            Rectangle {
                anchors.fill: parent
                color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                opacity: copied.running ? 0.85 : 0
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(120) } }
                MaterialSymbol { anchors.centerIn: parent; text: "check"; iconSize: 24; color: Appearance?.colors?.colOnPrimary ?? "#1e1e2e" }
            }
        }
        // Pin / unpin (always shown on a pin, on hover otherwise).
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 2
            width: 20; height: 20; radius: 10
            visible: cell.src === "pin" || cellHover.hovered
            color: Qt.rgba(0, 0, 0, 0.45)
            MaterialSymbol {
                anchors.centerIn: parent
                text: "keep"; iconSize: 13
                fill: cell.src === "pin" ? 1 : 0
                color: cell.src === "pin" ? (Appearance?.colors?.colPrimary ?? "#a6e3a1") : "#ffffff"
            }
            // Exclusive on press: the cell's own click (copy) doesn't fire too.
            TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: cell.togglePin() }
        }
    }

    // `qs -c ano ipc call shelf toggle`, or set a pill click to "shelf"
    // (anoSpot.actions.*).
    IpcHandler {
        target: "shelf"
        function toggle(): void { GlobalStates.anoSpotStashOpen = !GlobalStates.anoSpotStashOpen }
        function open(): void { GlobalStates.anoSpotStashOpen = true }
        function close(): void { GlobalStates.anoSpotStashOpen = false }
    }

    Variants {
        model: root.open ? Quickshell.screens : []

        PanelWindow {
            id: popoutWindow
            required property var modelData
            screen: modelData

            visible: root.open
            color: "transparent"

            implicitWidth: 380
            implicitHeight: 560

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:anospot:stash"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Anchor opposite the spot. If spot is top, popout drops down
            // from the top edge; if bottom, popout rises from the bottom.
            // For left/right spots we anchor to the same vertical edge.
            anchors {
                top: root.spotPosition === "top" || root.spotIsVertical
                bottom: root.spotPosition === "bottom" || root.spotIsVertical
                left: root.spotPosition === "left"
                right: root.spotPosition === "right"
            }
            margins {
                top: root.spotPosition === "top" ? 56 : 0  // clear the pill (~36px + gap)
                bottom: root.spotPosition === "bottom" ? 56 : 0
                left: root.spotPosition === "left" ? 56 : 0
                right: root.spotPosition === "right" ? 56 : 0
            }

            // Click-outside-to-close scrim. Layer-shell exclusionMode is
            // Ignore so we don't fight the bar; the scrim is invisible but
            // catches clicks anywhere outside the card.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: GlobalStates.anoSpotStashOpen = false
            }

            // The card itself
            SurfaceMaterial {
                id: card
                surface: "stash"
                anchors.centerIn: parent
                width: 380
                height: 560
                radius: Appearance?.rounding?.normal ?? 14
                color: Appearance?.colors?.colLayer0 ?? "#1e1e2e"
                // Glass-token opt-in for the popout surface. Inner cells
                // remain solid (Layer1) so the layered look reads cleanly
                // even with translucent themes like aurora/angel.
                border.width: Appearance?.glassTokens?.borderWidth ?? 1
                border.color: Appearance?.glassTokens?.borderColor
                            ?? Appearance?.colors?.colOutlineVariant
                            ?? "#444"
                opacity: Appearance?.glassTokens?.opacity ?? 1

                // Swallow clicks on the card so the scrim doesn't close it.
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // ─── Header: title + count + total size ───────────────
                    ColumnLayout {
                        id: headerCol
                        spacing: 2
                        Layout.fillWidth: true

                        RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: "inventory_2"
                                iconSize: 18
                                color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Shelf"
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                            }
                            StyledText {
                                visible: !AnoSpotStash.empty
                                text: `${AnoSpotStash.count} ${AnoSpotStash.count === 1 ? "item" : "items"} · ${AnoSpotStash.totalSizeText}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                opacity: 0.7
                                color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                            }
                        }
                    }

                    // ─── Item grid (dropped files) ────────────────────────
                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(contentHeight, 200)
                        visible: !AnoSpotStash.empty
                        cellWidth: 110
                        cellHeight: 100
                        clip: true
                        // Not flickable: a press-and-drag on a cell drags it out.
                        interactive: false
                        WheelScroll { view: grid }
                        model: AnoSpotStash.items

                        delegate: Item {
                            id: cellRoot
                            width: grid.cellWidth - 6
                            height: grid.cellHeight - 6

                            required property string fileURL
                            required property string filePath
                            required property string name
                            required property bool isDir
                            required property string sizeText

                            // Drag it out into another app (a file manager, a chat…).
                            Drag.dragType: Drag.Automatic
                            Drag.supportedActions: Qt.CopyAction
                            Drag.mimeData: ({ "text/uri-list": AnoSpotLogic.fileUri(cellRoot.filePath) })
                            Drag.active: cellDrag.active
                            DragHandler { id: cellDrag; target: null }

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Appearance?.colors?.colLayer1 ?? "#2b2930"
                                border.width: 1
                                border.color: Appearance?.colors?.colOutlineVariant ?? "#44444466"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 4

                                    // Thumbnail (image preview if it's an image, icon otherwise)
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 50

                                        Image {
                                            id: thumb
                                            anchors.fill: parent
                                            source: cellRoot.isDir ? "" : cellRoot.fileURL
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            visible: status === Image.Ready
                                            sourceSize.width: 200
                                            sourceSize.height: 100
                                        }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: !thumb.visible
                                            text: cellRoot.isDir ? "folder" : "draft"
                                            iconSize: 32
                                            color: Appearance?.colors?.colOnLayer0Subtle ?? "#a6adc8"
                                        }
                                    }

                                    // Filename (elided)
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cellRoot.name
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        elide: Text.ElideMiddle
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                    }
                                    // Size
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cellRoot.sizeText
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        opacity: 0.6
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                    }
                                }

                                // Per-item × removal button (top-right corner)
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 2
                                    width: 18; height: 18
                                    radius: 9
                                    color: removeMa.containsMouse
                                        ? (Appearance?.colors?.colError ?? "#f38ba8")
                                        : Qt.rgba(0, 0, 0, 0.4)
                                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 12
                                        color: "#ffffff"
                                    }
                                    MouseArea {
                                        id: removeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: AnoSpotStash.remove(cellRoot.filePath)
                                    }
                                }
                            }
                        }
                    }

                    // ─── Footer: actions toolbar ↔ LocalSend picker ──────
                    Loader {
                        id: footerLoader
                        Layout.fillWidth: true
                        visible: !AnoSpotStash.empty
                        property string mode: "actions"   // "actions" | "localsend"
                        sourceComponent: mode === "localsend" ? localsendComp : actionsComp

                        // When the popout closes, snap back to actions mode.
                        Connections {
                            target: GlobalStates
                            function onAnoSpotStashOpenChanged() {
                                if (!GlobalStates.anoSpotStashOpen) {
                                    footerLoader.mode = "actions";
                                    AnoSpotStash.localSendStop();
                                }
                            }
                        }
                    }

                    // ─── Shelf: pins, recent screenshots and clipboard ────
                    StyledText {
                        text: shelfGrid.count ? "Pinned & recent" : "Pins, recent screenshots and copies show here"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        opacity: 0.7
                        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                    }
                    GridView {
                        id: shelfGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        cellWidth: Math.floor(width / 4)
                        cellHeight: 92
                        clip: true
                        interactive: false
                        WheelScroll { view: shelfGrid }
                        model: AnoSpotLogic.shelf(Cliphist.pins, AnoSpotStash.shots,
                            Cliphist.entries.slice(0, AnoSpotStash.shelfSize * 2).map(e => ({ line: e, info: Cliphist.entryInfo(e) })),
                            AnoSpotStash.shelfSize)
                        delegate: ShelfCell { }
                    }

                    // ─── Action toolbar ──────────────────────────────────
                    Component {
                        id: actionsComp
                        ColumnLayout {
                            spacing: 6

                            // Built-in actions row 1
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                AnoSpotActionButton {
                                    iconName: "send"; label: "LocalSend"
                                    accent: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                                    onActivated: {
                                        footerLoader.mode = "localsend";
                                        AnoSpotStash.localSendDiscover();
                                    }
                                }
                                AnoSpotActionButton {
                                    iconName: "open_in_new"; label: "Open"
                                    onActivated: AnoSpotStash.openAll()
                                }
                                AnoSpotActionButton {
                                    iconName: "content_copy"; label: "Copy path"
                                    onActivated: AnoSpotStash.copyPaths()
                                }
                                AnoSpotActionButton {
                                    iconName: "drive_file_move"; label: "Move to…"
                                    onActivated: moveToProc.running = true
                                }
                                AnoSpotActionButton {
                                    iconName: "folder_open"; label: "Reveal"
                                    onActivated: AnoSpotStash.revealFirst()
                                }
                            }

                            // Custom user-defined rules (each renders as a button)
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: customRulesRepeater.count > 0

                                Repeater {
                                    id: customRulesRepeater
                                    model: Config.options?.anoSpot?.dropTargets ?? []

                                    AnoSpotActionButton {
                                        required property var modelData
                                        iconName: modelData.icon ?? "play_arrow"
                                        label: modelData.name ?? "Custom"
                                        onActivated: AnoSpotStash.runCustomRule(modelData)
                                    }
                                }
                            }

                            // Bottom row: clear-all
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }

                                RippleButton {
                                    implicitHeight: 30
                                    buttonRadius: 8
                                    colBackground: Appearance?.colors?.colLayer1 ?? "#2b2930"
                                    contentItem: RowLayout {
                                        spacing: 6
                                        MaterialSymbol {
                                            text: "delete_sweep"; iconSize: 14
                                            color: Appearance?.colors?.colError ?? "#f38ba8"
                                        }
                                        StyledText {
                                            text: "Clear all"; font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                        }
                                    }
                                    onClicked: AnoSpotStash.clear()
                                }
                            }
                        }
                    }

                    // ─── LocalSend picker ────────────────────────────────
                    Component {
                        id: localsendComp
                        ColumnLayout {
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                MaterialSymbol {
                                    text: "wifi_find"; iconSize: 14
                                    color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: AnoSpotStash.discoverState === "scanning"
                                        ? "Scanning for LocalSend devices…"
                                        : (AnoSpotStash.discoveredDevices.count === 0
                                            ? "No devices found on this network"
                                            : `${AnoSpotStash.discoveredDevices.count} device${AnoSpotStash.discoveredDevices.count === 1 ? "" : "s"} found`)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                }
                                RippleButton {
                                    implicitHeight: 26
                                    buttonRadius: 6
                                    contentItem: RowLayout {
                                        spacing: 4
                                        MaterialSymbol { text: "refresh"; iconSize: 12 }
                                        StyledText { text: "Rescan"; font.pixelSize: Appearance.font.pixelSize.smaller }
                                    }
                                    onClicked: AnoSpotStash.localSendDiscover()
                                }
                                RippleButton {
                                    implicitHeight: 26
                                    buttonRadius: 6
                                    contentItem: RowLayout {
                                        spacing: 4
                                        MaterialSymbol { text: "arrow_back"; iconSize: 12 }
                                        StyledText { text: "Back"; font.pixelSize: Appearance.font.pixelSize.smaller }
                                    }
                                    onClicked: {
                                        AnoSpotStash.localSendStop();
                                        footerLoader.mode = "actions";
                                    }
                                }
                            }

                            // Device list
                            ListView {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(120, contentHeight)
                                clip: true
                                model: AnoSpotStash.discoveredDevices
                                spacing: 4

                                delegate: Rectangle {
                                    width: ListView.view ? ListView.view.width : 0
                                    height: 32
                                    radius: 6
                                    color: deviceMa.containsMouse
                                        ? (Appearance?.colors?.colLayer2 ?? "#3a3845")
                                        : (Appearance?.colors?.colLayer1 ?? "#2b2930")
                                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(100) } }

                                    required property string alias
                                    required property string ip

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6
                                        MaterialSymbol {
                                            text: "smartphone"; iconSize: 14
                                            color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: parent.parent.alias
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            elide: Text.ElideRight
                                            color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                        }
                                        StyledText {
                                            text: parent.parent.ip
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            opacity: 0.55
                                            color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                        }
                                    }

                                    MouseArea {
                                        id: deviceMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            AnoSpotStash.localSendAll(parent.ip);
                                            // Return to actions; user sees notify-send for results.
                                            footerLoader.mode = "actions";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Move-to picker via zenity. User picks a directory; we mv every
            // staged item there and refresh the stash. Out of band of the
            // service so that the popout stays free of zenity coupling.
            Process {
                id: moveToProc
                command: ["bash", "-c",
                    "set -e; " +
                    "dir=$(zenity --file-selection --directory --title='Move stashed items to…' 2>/dev/null) || exit 0; " +
                    "[ -z \"$dir\" ] && exit 0; " +
                    "for f in '" + AnoSpotStash.stashDir.replace(/'/g, "'\\''") + "'/*; do " +
                    "  [ -e \"$f\" ] && mv -f -- \"$f\" \"$dir/\" || true; " +
                    "done"]
                onExited: AnoSpotStash.refresh()
            }

            // Keys can't attach to a window (only to Items): a focused Item that
            // fills it receives the window's keys.
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) GlobalStates.anoSpotStashOpen = false;
                }
            }
        }
    }
}
