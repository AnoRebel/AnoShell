import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// To-do (todo.enable), synced both ways with todo.txt. Animated checkboxes
// and strike-through, double-click to edit, priorities "(A) ", due:dates,
// +projects and @contexts as chips, done tasks folded under "Done", Undo.
Rectangle {
    id: root
    implicitHeight: col.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    property bool showDone: false
    readonly property int doneCount: Todo.items.filter(i => i.done).length
    readonly property int total: Todo.items.length

    // What a todo.txt line shows: its title, priority, due date and tags.
    function meta(text) {
        let t = Todo.expandDue(text), pri = "" // due:today etc. typed elsewhere, too
        const p = t.match(/^\(([A-Z])\) /)
        if (p) { pri = p[1]; t = t.slice(4) }
        const due = (t.match(/(?:^|\s)due:(\d{4}-\d{2}-\d{2})(?=\s|$)/) ?? [])[1] ?? ""
        const tags = (t.match(/(?:^|\s)[+@]\S+/g) ?? []).map(x => x.trim())
        t = t.replace(/(?:^|\s)due:\d{4}-\d{2}-\d{2}(?=\s|$)/g, "").replace(/(?:^|\s)[+@]\S+/g, "").trim()
        return { title: t || text, pri: pri, due: due, tags: tags }
    }
    function dueLabel(d) {
        const at = new Date(d + "T00:00:00")
        const days = Math.round((at - new Date(Todo.today(0) + "T00:00:00")) / 86400000)
        if (days < 0) return { text: days === -1 ? "Yesterday" : `${-days} days ago`, tone: "error" }
        if (days === 0) return { text: "Today", tone: "primary" }
        if (days === 1) return { text: "Tomorrow", tone: "primary" }
        return { text: Qt.formatDate(at, days < 7 ? "dddd" : "d MMM"), tone: "neutral" }
    }

    // Rows are diffed into a ListModel (not rebuilt), so adding, removing
    // and moving a task (open ones first, then done ones) animate.
    ListModel { id: rows }
    function target() {
        const seen = {}, out = []
        const push = (it, i) => {
            seen[it.text] = (seen[it.text] ?? 0) + 1
            out.push({ key: it.text + "\u0000" + seen[it.text], idx: i, done: it.done, line: it.text })
        }
        Todo.items.forEach((it, i) => { if (!it.done) push(it, i) })
        // The "Done" header is a row too, so it moves with the list.
        if (Todo.items.some(it => it.done)) out.push({ key: "\u0001done", idx: -1, done: true, line: "" })
        Todo.items.forEach((it, i) => { if (it.done) push(it, i) })
        return out
    }
    function sync() {
        const t = root.target()
        const keys = new Set(t.map(x => x.key))
        for (let i = 0; i < t.length; i++) {
            while (i < rows.count && !keys.has(rows.get(i).key)) rows.remove(i)
            if (i < rows.count && rows.get(i).key === t[i].key) { rows.set(i, t[i]); continue }
            let j = -1
            for (let k = i + 1; k < rows.count; k++) if (rows.get(k).key === t[i].key) { j = k; break }
            if (j >= 0) { rows.move(j, i, 1); rows.set(i, t[i]) } else rows.insert(i, t[i])
        }
        while (rows.count > t.length) rows.remove(rows.count - 1)
    }
    Connections { target: Todo; function onItemsChanged() { root.sync() } }
    Component.onCompleted: root.sync()

    component Chip: Rectangle {
        id: chip
        property string icon
        property string label
        property string tone: "neutral"
        readonly property color fg: tone === "error" ? Appearance.colors.colError : tone === "primary" ? Appearance.colors.colPrimary
            : tone === "tertiary" ? Appearance.colors.colTertiary : Appearance.colors.colSubtext
        implicitHeight: 18
        implicitWidth: chipRow.implicitWidth + 12
        radius: 9
        color: tone === "neutral" ? Appearance.colors.colLayer2 : Qt.rgba(fg.r, fg.g, fg.b, 0.14)
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 3
            MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: chip.icon; iconSize: 12; color: chip.fg }
            StyledText { anchors.verticalCenter: parent.verticalCenter; text: chip.label; font.pixelSize: Appearance.font.pixelSize.smallest; color: chip.fg }
        }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialSymbol { text: "checklist"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
            StyledText { Layout.fillWidth: true; text: "To-do"; font.weight: Font.DemiBold }
            StyledText {
                visible: root.total > 0
                text: root.doneCount === root.total ? "All done" : `${root.total - root.doneCount} left`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            ToolbarButton {
                visible: root.doneCount > 0
                iconName: "cleaning_services"; iconSize: 18; toolTipText: "Remove done tasks"
                onClicked: Todo.clearDone()
            }
        }
        // Progress
        Rectangle {
            Layout.fillWidth: true
            visible: root.total > 0
            implicitHeight: 4
            radius: 2
            color: Appearance.colors.colLayer2
            Rectangle {
                height: parent.height
                radius: 2
                width: parent.width * (root.total ? root.doneCount / root.total : 0)
                color: root.doneCount === root.total ? Appearance.colors.colSuccess : Appearance.colors.colPrimary
                Behavior on width { MotionSpring { token: "snappy" } }
                Behavior on color { CAnim {} }
            }
        }

        // Empty state
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 4
            visible: root.total === 0
            spacing: 2
            MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "task_alt"; iconSize: 28; color: Appearance.colors.colSubtext }
            StyledText { Layout.alignment: Qt.AlignHCenter; text: "Nothing to do"; color: Appearance.colors.colSubtext }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            // A spring retargets smoothly while folding rows change the height every frame.
            Behavior on Layout.preferredHeight { MotionSpring { token: "settle" } }
            visible: root.total > 0
            interactive: false
            model: rows
            spacing: 0
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.animation.elementMoveFast.duration }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial }
                }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration }
                    NumberAnimation { property: "x"; to: 32; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.InCubic }
                }
            }
            displaced: Transition { NumberAnimation { property: "y"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard } }
            // The moving row dims while it passes over the others.
            move: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "y"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
                    NumberAnimation { property: "opacity"; from: 0.35; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InQuad }
                }
            }

            delegate: Item {
                id: row
                required property int index
                required property int idx
                required property bool done
                required property string line
                readonly property bool isHeader: idx < 0
                readonly property var m: root.meta(line)
                // Checked: the box and strike animate here first, then the task moves.
                property bool pending: false
                readonly property bool looksDone: done !== pending
                property bool editing: false
                readonly property bool folded: done && !root.showDone && !isHeader
                onDoneChanged: pending = false
                function check() {
                    if (pending) return
                    pending = true
                    commit.restart()
                }
                Timer { id: commit; interval: 420; onTriggered: { Todo.toggle(row.idx); row.pending = false } }

                width: list.width
                height: isHeader ? 30 : folded ? 0 : body.implicitHeight + 10
                opacity: folded ? 0 : 1
                clip: true
                Behavior on height { Anim {} }
                Behavior on opacity { Anim {} }

                // "Done · n": folds the done tasks away.
                RowLayout {
                    visible: row.isHeader
                    anchors { fill: parent; leftMargin: 6 }
                    spacing: 4
                    MaterialSymbol {
                        text: "expand_more"; iconSize: 18; color: Appearance.colors.colSubtext
                        rotation: root.showDone ? 0 : -90
                        Behavior on rotation { Anim {} }
                    }
                    StyledText { Layout.fillWidth: true; text: `Done · ${root.doneCount}`; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                }
                MouseArea {
                    visible: row.isHeader
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showDone = !root.showDone
                }

                Rectangle {
                    visible: !row.isHeader
                    anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                    radius: Appearance.rounding.small
                    color: hover.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                    Behavior on color { CAnim {} }
                }
                HoverHandler { id: hover }

                RowLayout {
                    id: body
                    visible: !row.isHeader
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 2 }
                    spacing: 10

                    // Checkbox: fills, then the tick springs in.
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 1
                        implicitWidth: 20; implicitHeight: 20
                        radius: 6
                        color: row.looksDone ? Appearance.colors.colPrimary : "transparent"
                        border.width: row.looksDone ? 0 : 2
                        border.color: row.m.pri === "A" ? Appearance.colors.colError : row.m.pri === "B" ? Appearance.colors.colTertiary : Appearance.colors.colOutline
                        Behavior on color { CAnim {} }
                        scale: box.pressed ? 0.85 : 1
                        Behavior on scale { MotionSpring { token: "snappy" } }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"; iconSize: 16; fill: 1
                            color: Appearance.colors.colOnPrimary
                            scale: row.looksDone ? 1 : 0
                            rotation: row.looksDone ? 0 : -60
                            Behavior on scale { MotionSpring { token: "snappy" } }
                            Behavior on rotation { Anim {} }
                        }
                        MouseArea { id: box; anchors { fill: parent; margins: -6 } cursorShape: Qt.PointingHandCursor; onClicked: row.check() }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 3
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: row.editing ? edit.implicitHeight + 6 : title.implicitHeight
                            StyledText {
                                id: title
                                visible: !row.editing
                                width: parent.width
                                text: row.m.title
                                wrapMode: Text.Wrap
                                color: row.looksDone ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                                Behavior on color { CAnim {} }
                                font.strikeout: row.looksDone && lineCount > 1
                            }
                            // One line: a strike that draws across it.
                            Rectangle {
                                visible: !row.editing && title.lineCount === 1
                                y: Math.round(title.implicitHeight / 2)
                                height: 1.5
                                radius: 1
                                color: Appearance.colors.colSubtext
                                width: row.looksDone ? title.contentWidth : 0
                                Behavior on width { Anim { duration: 300 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                visible: !row.editing
                                onDoubleClicked: { row.editing = true; edit.text = row.line; edit.forceActiveFocus(); edit.selectAll() }
                            }
                            Rectangle {
                                visible: row.editing
                                anchors.fill: parent
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                StyledTextInput {
                                    id: edit
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    onAccepted: { Todo.setText(row.idx, text); row.editing = false }
                                    Keys.onEscapePressed: row.editing = false
                                    onActiveFocusChanged: if (!activeFocus && row.editing) { Todo.setText(row.idx, text); row.editing = false }
                                }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            visible: !row.editing && (row.m.pri !== "" || row.m.due !== "" || row.m.tags.length > 0)
                            Chip { visible: row.m.pri !== ""; icon: "flag"; label: `Priority ${row.m.pri}`; tone: row.m.pri === "A" ? "error" : row.m.pri === "B" ? "tertiary" : "neutral" }
                            Chip {
                                visible: row.m.due !== ""
                                readonly property var d: row.m.due ? root.dueLabel(row.m.due) : ({ text: "", tone: "neutral" })
                                icon: "event"; label: d.text; tone: row.looksDone ? "neutral" : d.tone
                            }
                            Repeater {
                                model: row.m.tags
                                delegate: Chip {
                                    required property string modelData
                                    icon: modelData[0] === "+" ? "folder" : "alternate_email"
                                    label: modelData.slice(1)
                                }
                            }
                        }
                    }

                    ToolbarButton {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        iconName: "close"; iconSize: 16; toolTipText: "Remove"
                        opacity: hover.hovered && !row.editing ? 1 : 0
                        enabled: opacity > 0
                        Behavior on opacity { Anim {} }
                        onClicked: Todo.remove(row.idx)
                    }
                }
            }
        }

        // Undo a removal
        Rectangle {
            id: undoBar
            readonly property bool show: Todo.lastRemoved !== null
            Layout.fillWidth: true
            Layout.preferredHeight: show ? 34 : 0
            opacity: show ? 1 : 0
            clip: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            Behavior on Layout.preferredHeight { Anim {} }
            Behavior on opacity { Anim {} }
            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 4 }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: `Removed “${root.meta(Todo.lastRemoved?.item?.text ?? "").title}”`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                RippleButton { buttonText: "Undo"; onClicked: Todo.undoRemove() }
            }
            Timer { running: undoBar.show; interval: 6000; onTriggered: Todo.lastRemoved = null }
        }

        // Add
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            border.width: input.activeFocus ? 1 : 0
            border.color: Appearance.colors.colPrimary
            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                spacing: 6
                MaterialSymbol { text: "add"; iconSize: 18; color: input.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colSubtext }
                StyledTextInput {
                    id: input
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    verticalAlignment: TextInput.AlignVCenter
                    onAccepted: { Todo.add(text); text = "" }
                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: input.text === ""
                        elide: Text.ElideRight
                        text: input.activeFocus ? "(A) priority · due:tomorrow · +project · @context" : "Add a task"
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
