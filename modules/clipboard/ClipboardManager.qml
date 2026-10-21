import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Clipboard manager overlay — browse clipboard history from cliphist,
 * search/filter entries, click to paste, right-click to copy without paste,
 * view images inline, clear all, and pin entries.
 * Text and image entries are shown with different styling.
 */
Scope {
    id: root
    property string searchQuery: ""

    readonly property var filteredEntries: {
        if (!GlobalStates.clipboardOpen) return []
        if (searchQuery.length === 0) return Cliphist.entries
        const q = searchQuery.toLowerCase()
        return Cliphist.entries.filter(entry => {
            const text = entry.split("\t").slice(1).join("\t").toLowerCase()
            return text.includes(q)
        })
    }

    Component.onCompleted: Cliphist.refresh()

    // The large preview over the list: an image, or a video's still with Open.
    property string previewPath: ""
    property string previewKind: ""
    property string previewOpen: ""     // the file Open hands to its default app
    function showPreview(path, kind, file) {
        if (!path || path === "!") return
        root.previewKind = kind
        root.previewOpen = file ?? ""
        root.previewPath = path
    }
    function previewEntry(entry) {
        const info = Cliphist.entryInfo(entry)
        if (info.kind === "image") root.showPreview(Cliphist.preview("img:" + info.id), "image")
        else if (info.kind === "files") {
            const f = info.files[0]
            root.showPreview(f.kind === "image" ? f.path : f.kind === "video" ? Cliphist.preview("vid:" + f.path) : "", f.kind, f.path)
        }
    }

    Connections {
        target: GlobalStates
        function onClipboardOpenChanged() {
            root.previewPath = ""
            if (GlobalStates.clipboardOpen) { root.searchQuery = ""; Cliphist.refresh() }
        }
    }

    PanelWindow {
        id: clipWindow
        visible: GlobalStates.clipboardOpen

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.clipboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }

        // Keys can't attach to a window (only to Items); a Shortcut works there.

        Shortcut { sequence: "Escape"; onActivated: { if (root.previewPath) root.previewPath = ""; else GlobalStates.clipboardOpen = false } }

        // Click outside to close; nothing dims the desktop behind it.
        MouseArea { anchors.fill: parent; onClicked: GlobalStates.clipboardOpen = false }

        // Card
        SurfaceMaterial {
            id: clipCard
            surface: "clipboard"
            anchors.centerIn: parent
            width: Math.min(600, parent.width * 0.7)
            height: Math.min(650, parent.height * 0.8)
            radius: Appearance?.rounding.windowRounding ?? 20
            color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
            clip: true

            opacity: GlobalStates.clipboardOpen ? 1 : 0
            scale: GlobalStates.clipboardOpen ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
            Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 12

                // Header
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    MaterialSymbol { text: "content_paste"; iconSize: 24; color: Appearance?.colors.colPrimary ?? "#65558F" }
                    StyledText { text: "Clipboard"; font.pixelSize: Appearance?.font.pixelSize.huger ?? 22; font.weight: Font.Bold; Layout.fillWidth: true }
                    StyledText { text: `${Cliphist.entries.length} items`; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4 }

                    // Superpaste
                    RippleButtonWithIcon {
                        iconName: "content_paste_go"
                        buttonText: "Superpaste"
                        buttonRadius: Appearance?.rounding.full ?? 9999
                        onClicked: { Cliphist.superpaste(5); GlobalStates.clipboardOpen = false }
                        StyledToolTip { text: "Paste last 5 items rapidly" }
                    }

                    // Clear all
                    ToolbarButton {
                        iconName: "delete_sweep"; iconSize: 20
                        toolTipText: "Clear all history"
                        onClicked: Cliphist.wipe()
                    }

                    ToolbarButton { iconName: "close"; iconSize: 20; onClicked: GlobalStates.clipboardOpen = false }
                }

                // Search
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 40; radius: 20
                    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        spacing: 8
                        MaterialSymbol { text: "search"; iconSize: 20; opacity: 0.5 }
                        StyledTextInput {
                            id: clipSearch
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.small; focus: GlobalStates.clipboardOpen
                            onTextChanged: { root.searchQuery = text; entryList.currentIndex = 0 }
                            Keys.onPressed: event => {
                                const cur = root.filteredEntries[entryList.currentIndex]
                                if (event.key === Qt.Key_Down) { entryList.incrementCurrentIndex(); event.accepted = true }
                                else if (event.key === Qt.Key_Up) { entryList.decrementCurrentIndex(); event.accepted = true }
                                else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && cur) {
                                    Cliphist.paste(cur); GlobalStates.clipboardOpen = false; event.accepted = true
                                } else if (event.key === Qt.Key_Delete && text === "" && cur) { Cliphist.deleteEntry(cur); event.accepted = true }
                                else if (event.key === Qt.Key_Space && text === "" && cur) { root.previewEntry(cur); event.accepted = true }
                            }
                            StyledText {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: "Search clipboard..."; opacity: 0.4; font.pixelSize: Appearance.font.pixelSize.small
                                visible: !clipSearch.text || clipSearch.text.length === 0
                            }
                        }
                        ToolbarButton { iconName: "close"; iconSize: 16; visible: root.searchQuery.length > 0; onClicked: clipSearch.text = "" }
                    }
                }

                // Entry list — virtualized: history can hold hundreds of entries,
                // and building every row up front froze the shell for seconds.
                ListView {
                    id: entryList
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.filteredEntries

                    StyledText {
                        visible: root.filteredEntries.length === 0
                        text: root.searchQuery.length > 0 ? "No matching entries" : "Clipboard is empty"
                        font.pixelSize: Appearance.font.pixelSize.small; opacity: 0.4
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 40
                    }

                    // Keyboard: the search field drives the selection.
                    currentIndex: 0
                    highlightMoveDuration: 0
                    onCountChanged: if (currentIndex >= count) currentIndex = Math.max(0, count - 1)

                    delegate: Rectangle {
                        id: row
                        required property string modelData
                        required property int index
                        readonly property var info: Cliphist.entryInfo(modelData)
                        readonly property bool selected: ListView.isCurrentItem
                        readonly property real contentWidth: entryList.width - 160 // minus the icon and the three actions
                        width: entryList.width
                        implicitHeight: entryContent.implicitHeight + 12
                        radius: Appearance?.rounding.small ?? 8
                        color: row.selected || entryMA.containsMouse ? Appearance.colors.colLayer1Hover : (index % 2 === 0 ? Qt.rgba(1,1,1,0.02) : "transparent")
                        border.width: row.selected ? 1 : 0
                        border.color: Appearance?.colors.colPrimary ?? "#65558F"
                        Behavior on color { CAnim {} }

                        // Previews are made as rows come into view (the list is virtualized).
                        function requestPreviews() {
                            if (info.needsText) Cliphist.requestText(info.id)
                            else if (info.kind === "image") Cliphist.requestImage(info.id, info.ext)
                            else if (info.kind === "files")
                                for (const f of info.files.slice(0, 4)) if (f.kind === "video") Cliphist.requestVideoFrame(f.path)
                        }
                        Component.onCompleted: requestPreviews()
                        onInfoChanged: requestPreviews() // a file list is known in full a moment later

                        RowLayout {
                            id: entryContent
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                            spacing: 8

                            MaterialSymbol {
                                text: ({ image: "image", files: "folder_open", color: "palette", text: "text_snippet" })[info.kind]
                                iconSize: 18; opacity: 0.4
                                color: info.kind === "text" ? Appearance.colors.colOnLayer1 : Appearance.colors.colPrimary
                                Layout.alignment: Qt.AlignTop
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 4

                                // ── Image: a thumbnail at the image's own shape ──
                                Rectangle {
                                    id: imgFrame
                                    visible: info.kind === "image"
                                    readonly property real aspect: info.width && info.height ? info.width / info.height : 1.6
                                    readonly property string path: Cliphist.preview("img:" + info.id)
                                    Layout.preferredHeight: visible ? Math.round(Math.min(150, Math.max(40, row.contentWidth / aspect))) : 0
                                    Layout.preferredWidth: visible ? Math.min(row.contentWidth, Layout.preferredHeight * aspect) : 0
                                    radius: 6
                                    color: Appearance.colors.colLayer1
                                    clip: true
                                    Image {
                                        id: thumb
                                        anchors.fill: parent
                                        source: imgFrame.path && imgFrame.path !== "!" ? "file://" + imgFrame.path : ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: false
                                        sourceSize.height: 300
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { Anim {} }
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: thumb.status !== Image.Ready
                                        text: imgFrame.path === "!" ? "broken_image" : "image"
                                        iconSize: 22; opacity: 0.3
                                    }
                                    ToolbarButton {
                                        anchors { right: parent.right; top: parent.top; margins: 4 }
                                        visible: thumb.status === Image.Ready && (entryMA.containsMouse || row.selected)
                                        iconName: "open_in_full"; iconSize: 14; toolTipText: "Preview (Space)"
                                        onClicked: root.showPreview(imgFrame.path, "image")
                                    }
                                }
                                StyledText {
                                    visible: info.kind === "image"
                                    text: info.kind === "image" ? `${info.ext.toUpperCase()} · ${info.width}×${info.height} · ${info.size}` : ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }

                                // ── Copied files: image / video thumbnails, icons for the rest ──
                                Flow {
                                    visible: info.kind === "files"
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: info.kind === "files" ? info.files.slice(0, 4) : []
                                        delegate: Column {
                                            id: tile
                                            required property var modelData
                                            readonly property string still: modelData.kind === "image" ? modelData.path
                                                : modelData.kind === "video" ? Cliphist.preview("vid:" + modelData.path) : ""
                                            spacing: 2
                                            width: 96
                                            Rectangle {
                                                width: 96; height: 72
                                                radius: 6
                                                color: Appearance.colors.colLayer1
                                                clip: true
                                                Image {
                                                    id: tileImg
                                                    anchors.fill: parent
                                                    source: tile.still && tile.still !== "!" ? "file://" + tile.still : ""
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    sourceSize.width: 192
                                                    opacity: status === Image.Ready ? 1 : 0
                                                    Behavior on opacity { Anim {} }
                                                }
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    visible: tileImg.status !== Image.Ready
                                                    text: ({ image: "image", video: "movie", audio: "music_note", pdf: "picture_as_pdf" })[tile.modelData.kind] ?? "draft"
                                                    iconSize: 26; opacity: 0.45
                                                }
                                                Rectangle { // a play badge on video stills
                                                    visible: tile.modelData.kind === "video" && tileImg.status === Image.Ready
                                                    anchors.centerIn: parent
                                                    width: 28; height: 28; radius: 14
                                                    color: Qt.rgba(0, 0, 0, 0.55)
                                                    MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; iconSize: 18; fill: 1; color: "white" }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    visible: tileImg.status === Image.Ready
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.showPreview(tile.modelData.kind === "image" ? tile.modelData.path : tile.still, tile.modelData.kind, tile.modelData.path)
                                                }
                                            }
                                            StyledText {
                                                width: parent.width
                                                text: tile.modelData.name
                                                elide: Text.ElideMiddle
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                            }
                                        }
                                    }
                                    StyledText {
                                        visible: info.kind === "files" && info.files.length > 4
                                        text: info.kind === "files" ? `+${info.files.length - 4} more` : ""
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                // ── A colour value: its swatch ──
                                RowLayout {
                                    visible: info.kind === "color"
                                    spacing: 8
                                    Rectangle {
                                        implicitWidth: 28; implicitHeight: 28; radius: 14
                                        color: info.kind === "color" ? info.color : "transparent"
                                        border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                    }
                                    StyledText { text: info.text; font.family: Appearance.font.family.mono; font.pixelSize: Appearance.font.pixelSize.small }
                                }

                                // ── Text ──
                                StyledText {
                                    visible: info.kind === "text"
                                    text: info.kind === "text" ? info.text.substring(0, 300) + (info.text.length > 300 ? "..." : "") : ""
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    wrapMode: Text.Wrap; maximumLineCount: 4
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }

                            // Actions
                            RowLayout {
                                spacing: 2; Layout.alignment: Qt.AlignTop
                                ToolbarButton {
                                    iconName: "content_copy"; iconSize: 14
                                    toolTipText: "Copy to clipboard"
                                    onClicked: Cliphist.copy(modelData)
                                }
                                ToolbarButton {
                                    iconName: "content_paste"; iconSize: 14
                                    toolTipText: "Paste"
                                    onClicked: { Cliphist.paste(modelData); GlobalStates.clipboardOpen = false }
                                }
                                ToolbarButton {
                                    iconName: "delete"; iconSize: 14
                                    toolTipText: "Delete entry"
                                    onClicked: Cliphist.deleteEntry(modelData)
                                }
                            }
                        }

                        MouseArea {
                            id: entryMA
                            anchors.fill: parent; hoverEnabled: true; z: -1
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: entryList.currentIndex = row.index
                            onClicked: event => {
                                if (event.button === Qt.RightButton) Cliphist.copy(modelData)
                                else { Cliphist.paste(modelData); GlobalStates.clipboardOpen = false }
                            }
                        }
                    }
                }

                // Footer
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    StyledText { text: "↑↓ select · Enter paste · Space preview · Delete remove · Right-click copy · Esc close"; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.3; Layout.fillWidth: true }
                }
            }

            // Large preview
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.rgba(0, 0, 0, 0.85)
                opacity: root.previewPath ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { Anim {} }
                MouseArea { anchors.fill: parent; onClicked: root.previewPath = "" }
                Image {
                    id: big
                    anchors { fill: parent; margins: 24; bottomMargin: 64 }
                    source: root.previewPath ? "file://" + root.previewPath : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    sourceSize.width: 1600
                    scale: root.previewPath ? 1 : 0.94
                    Behavior on scale { MotionSpring { token: "snappy" } }
                }
                RowLayout {
                    anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 }
                    spacing: 8
                    StyledText {
                        visible: big.status === Image.Ready && root.previewKind === "video"
                        text: "A frame from the video"
                        color: "white"; opacity: 0.7
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    RippleButton {
                        visible: root.previewOpen !== ""
                        buttonText: root.previewKind === "video" ? "Play" : "Open"
                        onClicked: { Qt.openUrlExternally("file://" + root.previewOpen); GlobalStates.clipboardOpen = false }
                    }
                    RippleButton { buttonText: "Close"; onClicked: root.previewPath = "" }
                }
            }
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { GlobalStates.clipboardOpen = !GlobalStates.clipboardOpen }
        function open(): void { GlobalStates.clipboardOpen = true }
        function close(): void { GlobalStates.clipboardOpen = false }
    }
}
