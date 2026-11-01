pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.sidebarRight
import qs.services

/**
 * Scratchpad & Pins (services/Scratchpad.qml): tabs over the notepad, to-do,
 * clipboard and calendar, the pinned commands beside them, and a prompt bar
 * (">>" run, ">" pin, "t " to-do, "? " web, "?? " AI, else the note).
 * Ctrl+Tab cycles the tabs. Shared by the pill's grow-into and the
 * standalone panel.
 */
ColumnLayout {
    id: root
    signal closeRequested()

    property int tab: 0
    readonly property var tabs: [
        { label: "Notes", icon: "edit_note" },
        { label: "To-do", icon: "checklist" },
        { label: "Clipboard", icon: "content_paste" },
        { label: "Calendar", icon: "calendar_month" }
    ]
    // A ">" line waiting for terminal-or-background.
    property string pendingPin: ""
    property string status: ""
    // The AI answer shown over the tab (dismissed with its close button).
    property bool showAnswer: false

    spacing: 10

    Component.onCompleted: Qt.callLater(() => prompt.forceActiveFocus())
    onTabChanged: if (tab === 2) Cliphist.refresh()
    Shortcut { sequence: "Ctrl+Tab"; onActivated: root.tab = (root.tab + 1) % root.tabs.length }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab"]; onActivated: root.tab = (root.tab + root.tabs.length - 1) % root.tabs.length }
    Timer { id: statusClear; interval: 4000; onTriggered: root.status = "" }
    function say(text) { root.status = text; statusClear.restart() }

    function submit() {
        const line = prompt.text
        const p = Scratchpad.parse(line)
        if (!p.text) return
        if (p.kind === "pin") { root.pendingPin = p.text; return }
        const r = Scratchpad.submit(line)
        root.say(r.msg)
        if (!r.ok) return // the line stays, to fix or retry
        if (p.kind === "ai") root.showAnswer = true
        if (p.kind === "note") root.tab = 0
        if (p.kind === "todo") root.tab = 1
        prompt.text = ""
    }
    function choosePin(terminal) {
        root.say(Scratchpad.pin(root.pendingPin, terminal) ? "Pinned" : "Already pinned")
        root.pendingPin = ""
        prompt.text = ""
        prompt.forceActiveFocus()
    }

    // ── Header ───────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Rectangle {
            implicitWidth: 30; implicitHeight: 30; radius: Appearance.rounding.small
            color: Appearance.colors.colPrimaryContainer
            MaterialSymbol { anchors.centerIn: parent; text: "sticky_note_2"; iconSize: 18; fill: 1; color: Appearance.colors.colOnPrimaryContainer }
        }
        StyledText { text: "Scratchpad & Pins"; font.weight: Font.DemiBold }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: {
                const t = Notepad.tabs[Notepad.current]?.text ?? ""
                const lines = t ? t.split("\n").length : 0
                return `· ${lines} line${lines === 1 ? "" : "s"} · ${Scratchpad.pins.length} pinned`
            }
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        Rectangle {
            implicitWidth: tabRow.implicitWidth + 8; implicitHeight: 32
            radius: 16
            color: Appearance.colors.colLayer1
            Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: root.tabs
                    delegate: RippleButton {
                        id: tabBtn
                        required property var modelData
                        required property int index
                        readonly property bool current: root.tab === index
                        implicitHeight: 26
                        implicitWidth: tabContent.implicitWidth + 16
                        buttonRadius: 13
                        toggled: current
                        onClicked: root.tab = index
                        contentItem: Row {
                            id: tabContent
                            spacing: 4
                            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: tabBtn.modelData.icon; iconSize: 14
                                color: tabBtn.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                            StyledText { anchors.verticalCenter: parent.verticalCenter; text: tabBtn.modelData.label; font.pixelSize: Appearance.font.pixelSize.smaller
                                color: tabBtn.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                        }
                    }
                }
            }
        }
        ToolbarButton { iconName: "close"; iconSize: 18; toolTipText: "Close (Esc)"; onClicked: root.closeRequested() }
    }

    // ── Tab | Pins ───────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        // Sets the panel's height (the pill grows to the content's).
        Layout.preferredHeight: 300
        Layout.preferredWidth: 728
        spacing: 10

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                id: stack
                anchors.fill: parent
                currentIndex: root.tab

                NotepadCard { editorHeight: Math.max(80, stack.height - 66) }

                Rectangle {
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    StyledFlickable {
                        anchors.fill: parent
                        contentHeight: todoCard.implicitHeight
                        clip: true
                        TodoCard { id: todoCard; width: parent.width }
                    }
                }

                // Clipboard: pins first, then the history; a row copies.
                Rectangle {
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    ListView {
                        id: clipList
                        anchors { fill: parent; margins: 6 }
                        clip: true
                        spacing: 2
                        model: Cliphist.pins.concat(Cliphist.entries.slice(0, 60))
                        delegate: ItemRow {
                            id: clipRow
                            required property var modelData
                            readonly property bool pinned: Cliphist.isPin(modelData)
                            readonly property var info: pinned ? Cliphist.pinInfo(modelData) : Cliphist.entryInfo(modelData)
                            width: clipList.width
                            icon: pinned ? "push_pin" : ({ image: "image", files: "folder_open", color: "palette" })[info.kind] ?? "text_snippet"
                            title: info.kind === "image" ? `Image · ${info.width}×${info.height}` : String(info.text ?? "").replace(/\s+/g, " ").trim()
                            subtitle: pinned ? "Pinned · click copies" : "Click copies"
                            onActivated: { Cliphist.copyItem(clipRow.modelData); root.say("Copied") }
                        }
                        StyledText {
                            anchors.centerIn: parent
                            visible: clipList.count === 0
                            text: Cliphist.error || "The clipboard history is empty"
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Calendar: the next two weeks; a row copies "when · title".
                Rectangle {
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    ListView {
                        id: calList
                        anchors { fill: parent; margins: 6 }
                        clip: true
                        spacing: 2
                        model: stack.currentIndex === 3 ? CalendarEvents.getUpcomingEvents(14) : []
                        delegate: ItemRow {
                            id: calRow
                            required property var modelData
                            readonly property string when: Qt.formatDateTime(new Date(modelData.occurrence), "ddd d MMM · hh:mm")
                            width: calList.width
                            icon: CalendarEvents.getCategoryIcon(modelData.category)
                            title: modelData.title ?? ""
                            subtitle: `${calRow.when} · click copies`
                            onActivated: { Scratchpad.copy(`${calRow.when} · ${calRow.title}`); root.say("Copied") }
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: calList.count === 0
                            StyledText { Layout.alignment: Qt.AlignHCenter; text: "Nothing in the next two weeks"; color: Appearance.colors.colSubtext }
                            RippleButton {
                                Layout.alignment: Qt.AlignHCenter
                                implicitHeight: 30
                                buttonText: "Open the calendar"
                                onClicked: { root.closeRequested(); GlobalStates.calendarOpen = true }
                            }
                        }
                    }
                }
            }

            // The AI's answer, over the tab.
            Rectangle {
                anchors.fill: parent
                visible: root.showAnswer && Scratchpad.answer !== null
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: 1; border.color: Appearance.colors.colLayer0Border
                ColumnLayout {
                    anchors { fill: parent; margins: 10 }
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialSymbol { text: "neurology"; iconSize: 18; color: Appearance.colors.colPrimary }
                        StyledText {
                            Layout.fillWidth: true
                            text: Scratchpad.answer?.done ? "Answer" : "Answering…"
                            font.weight: Font.DemiBold
                        }
                        ToolbarButton { iconName: "content_copy"; iconSize: 16; toolTipText: "Copy"; enabled: !!Scratchpad.answer?.content
                            onClicked: { Scratchpad.copy(Scratchpad.answer.content); root.say("Copied") } }
                        ToolbarButton { iconName: "note_add"; iconSize: 16; toolTipText: "Save as note"; enabled: !!Scratchpad.answer?.done
                            onClicked: { Notepad.addTab(); Notepad.setText(Notepad.current, Scratchpad.answer.content); root.showAnswer = false; root.tab = 0 } }
                        ToolbarButton { iconName: "close"; iconSize: 16; toolTipText: "Dismiss"; onClicked: root.showAnswer = false }
                    }
                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: answerText.implicitHeight
                        clip: true
                        TextEdit {
                            id: answerText
                            width: parent.width
                            text: Scratchpad.answer?.content ?? ""
                            readOnly: true; selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            color: Appearance.colors.colOnLayer1
                            selectionColor: Appearance.colors.colPrimary
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }

        // Pinned commands.
        Rectangle {
            Layout.preferredWidth: 300
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            ListView {
                id: pinList
                anchors { fill: parent; margins: 6 }
                clip: true
                spacing: 2
                model: Scratchpad.pins
                delegate: ItemRow {
                    id: pinRow
                    required property var modelData
                    width: pinList.width
                    icon: "terminal"
                    mono: true
                    title: modelData.command
                    subtitle: `${modelData.terminal ? "In a terminal" : "In the background"} · click runs, Shift+click copies`
                    onActivated: mods => {
                        if (mods & Qt.ShiftModifier) { Scratchpad.copy(pinRow.modelData.command); root.say("Copied") }
                        else if (pinRow.modelData.terminal) { Scratchpad.runPin(pinRow.modelData); root.closeRequested() } // the terminal gets the keyboard
                        else { Scratchpad.runPin(pinRow.modelData); root.say("Running in the background") }
                    }
                    ToolbarButton {
                        iconName: pinRow.modelData.terminal ? "terminal" : "bolt"; iconSize: 16
                        toolTipText: pinRow.modelData.terminal ? "Runs in a terminal (click: background)" : "Runs in the background (click: terminal)"
                        onClicked: Scratchpad.setTerminal(pinRow.modelData.key, !pinRow.modelData.terminal)
                    }
                    ToolbarButton { iconName: "delete"; iconSize: 16; toolTipText: "Unpin"; onClicked: Scratchpad.unpin(pinRow.modelData.key) }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    visible: pinList.count === 0
                    MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "push_pin"; iconSize: 26; color: Appearance.colors.colSubtext }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "Type \">command\" below to pin a command"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    // ── Prompt ───────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 40
        radius: 20
        color: Appearance.colors.colLayer1
        border.width: prompt.activeFocus ? 1 : 0
        border.color: Appearance.colors.colPrimary

        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
            spacing: 8
            visible: root.pendingPin === ""
            MaterialSymbol {
                text: ({ run: "play_arrow", pin: "push_pin", todo: "checklist", web: "travel_explore", ai: "neurology", note: "edit_note" })[Scratchpad.parse(prompt.text).kind] ?? "search"
                iconSize: 18; color: Appearance.colors.colSubtext
            }
            StyledTextInput {
                id: prompt
                Layout.fillWidth: true
                clip: true
                Keys.onReturnPressed: root.submit()
                Keys.onEnterPressed: root.submit()
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    elide: Text.ElideRight
                    visible: !prompt.text
                    text: "Note · >cmd pin · >>cmd run · t to-do · ? web · ?? AI"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            StyledText {
                text: root.status || "Ctrl+Tab · Esc"
                color: root.status ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        // ">cmd": where it runs.
        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 6 }
            spacing: 6
            visible: root.pendingPin !== ""
            MaterialSymbol { text: "push_pin"; iconSize: 18; color: Appearance.colors.colPrimary }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: `Pin "${root.pendingPin}" to run`
            }
            RippleButton { implicitHeight: 30; buttonText: "In a terminal"; onClicked: root.choosePin(true) }
            RippleButton { implicitHeight: 30; buttonText: "In the background"; onClicked: root.choosePin(false) }
            ToolbarButton { iconName: "close"; iconSize: 16; toolTipText: "Cancel"; onClicked: { root.pendingPin = ""; prompt.forceActiveFocus() } }
        }
    }

    // A list row: icon, title, subtitle, trailing buttons; click activates
    // (with the keyboard modifiers).
    component ItemRow: Rectangle {
        id: itemRow
        property string icon: ""
        property string title: ""
        property string subtitle: ""
        property bool mono: false
        default property alias trailing: trail.data
        signal activated(int mods)
        implicitHeight: 46
        radius: Appearance.rounding.small
        color: rowHover.hovered ? Appearance.colors.colLayer1Hover : "transparent"
        HoverHandler { id: rowHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => itemRow.activated(mouse.modifiers)
        }
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 4 }
            spacing: 10
            Rectangle {
                implicitWidth: 30; implicitHeight: 30; radius: 15
                color: Appearance.colors.colLayer2
                MaterialSymbol { anchors.centerIn: parent; text: itemRow.icon; iconSize: 16; color: Appearance.colors.colOnLayer2 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: itemRow.title
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: itemRow.mono ? Appearance.font.family.monospace : Appearance.font.family.main
                    font.weight: Font.Medium
                }
                StyledText {
                    Layout.fillWidth: true
                    text: itemRow.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
            Row { id: trail; spacing: 0 }
        }
    }
}
