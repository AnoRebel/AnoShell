import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.reader.components

Item {
    id: detailView

    readonly property string fontDisplay: Appearance.font.family.title
    readonly property string fontBody:    Appearance.font.family.main

    signal backRequested()
    signal chapterSelected(string chapterId)

    // ── Library state ─────────────────────────────────────────────────────────
    readonly property bool _inLibrary:
        ReaderNovel.currentNovel ? ReaderNovel.isInLibrary(ReaderNovel.currentNovel.id) : false

    // ── Filter / sort state ───────────────────────────────────────────────────
    property bool   _sortAscending: false
    property string _chapterFilter: ""

    function reset() {
        _chapterFilter = ""
        _sortAscending = false
    }

    // ── Helper ────────────────────────────────────────────────────────────────
    function formatChapter(ch) {
        if (!ch) return "?"
        const match = String(ch).match(/\d+(\.\d+)?/)
        return match ? match[0] : String(ch)
    }

    // ── Processed (filtered + sorted) chapter list ────────────────────────────
    readonly property var _processedChapters: {
        if (!ReaderNovel.currentNovel) return []
        let chapters = ReaderNovel.currentNovel.chapters.slice()

        if (detailView._chapterFilter.trim() !== "") {
            const f = detailView._chapterFilter.trim().toLowerCase()
            chapters = chapters.filter(ch => {
                const num   = detailView.formatChapter(ch.chapter).toLowerCase()
                const title = (ch.title || "").toLowerCase()
                return num.includes(f) || title.includes(f)
            })
        }

        chapters.sort((a, b) => {
            const numA = parseFloat(detailView.formatChapter(a.chapter)) || 0
            const numB = parseFloat(detailView.formatChapter(b.chapter)) || 0
            return detailView._sortAscending ? numA - numB : numB - numA
        })

        return chapters
    }

    // ── Reading helpers (preserved from original) ─────────────────────────────
    function continueReading() {
        if (!ReaderNovel.currentNovel) return

        var entry = ReaderNovel.getLibraryEntry(ReaderNovel.currentNovel.id)
        var lastChapterId = entry ? entry.lastReadChapterId : null
        var targetChapter = null

        if (lastChapterId) {
            for (var i = 0; i < ReaderNovel.currentNovel.chapters.length; i++) {
                if (ReaderNovel.currentNovel.chapters[i].id === lastChapterId) {
                    targetChapter = ReaderNovel.currentNovel.chapters[i]
                    break
                }
            }
        }

        if (!targetChapter && ReaderNovel.currentNovel.chapters.length > 0)
            targetChapter = ReaderNovel.currentNovel.chapters[0]

        if (targetChapter) {
            ReaderNovel.fetchChapter(targetChapter.id)
            detailView.chapterSelected(targetChapter.id)
            if (detailView._inLibrary)
                ReaderNovel.updateLastRead(ReaderNovel.currentNovel.id, targetChapter.id, targetChapter.chapter)
        }
    }

    function readNext() {
        if (!ReaderNovel.currentNovel) return

        var entry = ReaderNovel.getLibraryEntry(ReaderNovel.currentNovel.id)
        var lastChapterId = entry ? entry.lastReadChapterId : null
        var targetChapter = null

        if (lastChapterId) {
            for (var i = 0; i < ReaderNovel.currentNovel.chapters.length - 1; i++) {
                if (ReaderNovel.currentNovel.chapters[i].id === lastChapterId) {
                    targetChapter = ReaderNovel.currentNovel.chapters[i + 1]
                    break
                }
            }
        }

        if (!targetChapter && ReaderNovel.currentNovel.chapters.length > 0)
            targetChapter = ReaderNovel.currentNovel.chapters[0]

        if (targetChapter) {
            ReaderNovel.fetchChapter(targetChapter.id)
            detailView.chapterSelected(targetChapter.id)
            if (detailView._inLibrary)
                ReaderNovel.updateLastRead(ReaderNovel.currentNovel.id, targetChapter.id, targetChapter.chapter)
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 56
            color: Appearance.colors.colLayer1; z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 6; rightMargin: 10 }
                spacing: 2

                // Back button
                Item {
                    width: 44; height: 44
                    Rectangle {
                        anchors.centerIn: parent; width: 34; height: 34; radius: 17
                        color: backArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(130) } }
                    }
                    Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 18; color: Appearance.m3colors.m3onSurfaceVariant }
                    MouseArea {
                        id: backArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: { ReaderNovel.clearDetail(); detailView.backRequested() }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.title : ""
                    font.family: detailView.fontDisplay
                    font.pixelSize: 15; color: Appearance.m3colors.m3onSurface; elide: Text.ElideRight
                }

                // Library toggle
                Item {
                    visible: ReaderNovel.currentNovel !== null
                    width: libBtnLabel.implicitWidth + 28; height: 34

                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: detailView._inLibrary ? Appearance.m3colors.m3primaryContainer : Appearance.colors.colLayer2
                        border.color: detailView._inLibrary ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                    }

                    Row {
                        anchors.centerIn: parent; spacing: 5
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: detailView._inLibrary ? "✓" : "+"
                            font.pixelSize: 11; font.bold: true
                            color: detailView._inLibrary ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                        }
                        StyledText {
                            id: libBtnLabel; anchors.verticalCenter: parent.verticalCenter
                            text: "Library"; font.family: detailView.fontBody
                            font.pixelSize: 11; font.letterSpacing: 0.3
                            color: detailView._inLibrary ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            if (detailView._inLibrary)
                                ReaderNovel.removeFromLibrary(ReaderNovel.currentNovel.id)
                            else
                                ReaderNovel.addToLibrary({
                                    id:       ReaderNovel.currentNovel.id,
                                    title:    ReaderNovel.currentNovel.title,
                                    coverUrl: ReaderNovel.currentNovel.coverUrl
                                })
                        }
                    }
                }
            }
        }

        // ── Hero banner ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: ReaderNovel.currentNovel !== null ? 160 : 0
            clip: true
            Behavior on Layout.preferredHeight { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

            // Blurred cover background
            Image {
                anchors.fill: parent
                source: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.coverUrl : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 360 // a faint backdrop: small is enough
                asynchronous: true; opacity: 0.2
            }

            // Gradient overlay
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.8) }
                    GradientStop { position: 1.0; color: Appearance.colors.colLayer0 }
                }
            }

            // Content row
            Row {
                anchors { fill: parent; margins: 14 }
                spacing: 14

                // Cover thumbnail
                Rectangle {
                    width: 90; height: 130; radius: 8
                    color: Appearance.colors.colLayer3; clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.coverUrl : ""
                        sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
                        fillMode: Image.PreserveAspectCrop; asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 8; color: "transparent"
                        border.color: Appearance.m3colors.m3outlineVariant; border.width: 1
                    }
                }

                Column {
                    width: parent.width - 104
                    spacing: 6; anchors.verticalCenter: parent.verticalCenter

                    // Status badge
                    Rectangle {
                        visible: ReaderNovel.currentNovel && ReaderNovel.currentNovel.status.length > 0
                        height: 18; width: statusTxt.implicitWidth + 14; radius: 9
                        color: ColorUtils.transparentize(Appearance.m3colors.m3tertiary, 0.15)
                        border.color: Appearance.m3colors.m3tertiary; border.width: 1

                        Text {
                            id: statusTxt; anchors.centerIn: parent
                            text: ReaderNovel.currentNovel ? (ReaderNovel.currentNovel.status || "").toUpperCase() : ""
                            font.family: detailView.fontBody; font.pixelSize: 9
                            font.letterSpacing: 1.2; font.bold: true; color: Appearance.m3colors.m3tertiary
                        }
                    }

                    // Author
                    StyledText {
                        width: parent.width
                        text: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.author : ""
                        font.family: detailView.fontBody; font.pixelSize: 12; font.bold: true
                        color: Appearance.m3colors.m3onSurface; elide: Text.ElideRight
                    }

                    // Genres
                    StyledText {
                        visible: ReaderNovel.currentNovel && ReaderNovel.currentNovel.genres.length > 0
                        width: parent.width
                        text: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.genres.join(" · ") : ""
                        font.family: detailView.fontBody; font.pixelSize: 10
                        color: Appearance.m3colors.m3primary; opacity: 0.85; elide: Text.ElideRight; font.letterSpacing: 0.2
                    }

                    // Description
                    StyledText {
                        width: parent.width
                        text: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.description : ""
                        font.family: detailView.fontBody; font.pixelSize: 11
                        color: Appearance.m3colors.m3onSurfaceVariant; wrapMode: Text.Wrap
                        maximumLineCount: 3; elide: Text.ElideRight; opacity: 0.8; lineHeight: 1.35
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.35
            }
        }

        // ── Chapter count + last-read strip ───────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 36
            color: Appearance.colors.colLayer2
            visible: ReaderNovel.currentNovel !== null

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }

                Text {
                    text: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.chapters.length + " chapters" : ""
                    font.family: detailView.fontBody; font.pixelSize: 11
                    font.letterSpacing: 1; color: Appearance.m3colors.m3onSurfaceVariant; opacity: 0.75
                }

                // The site stopped answering partway through the list
                Text {
                    visible: ReaderNovel.currentNovel !== null && ReaderNovel.currentNovel.partial
                    text: "· list incomplete — tap to load the rest"
                    font.family: detailView.fontBody; font.pixelSize: 10
                    color: Appearance.m3colors.m3tertiary
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ReaderNovel.retryDetail()
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    readonly property var _entry: ReaderNovel.currentNovel
                        ? ReaderNovel.getLibraryEntry(ReaderNovel.currentNovel.id) : null
                    visible: _entry !== null && _entry !== undefined
                        && _entry.lastReadChapterNum !== "" && _entry.lastReadChapterNum !== undefined
                    height: 20; width: lastReadTxt.implicitWidth + 18; radius: 10
                    color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.12)
                    border.color: Appearance.m3colors.m3primary; border.width: 1

                    Text {
                        id: lastReadTxt; anchors.centerIn: parent
                        text: {
                            var e = ReaderNovel.currentNovel ? ReaderNovel.getLibraryEntry(ReaderNovel.currentNovel.id) : null
                            return e ? "Last: Ch. " + e.lastReadChapterNum : ""
                        }
                        font.family: detailView.fontBody; font.pixelSize: 9
                        font.letterSpacing: 0.8; color: Appearance.m3colors.m3primary
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.3
            }
        }

        // ── Continue / Next Chapter buttons ───────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 48
            color: Appearance.colors.colLayer2
            visible: ReaderNovel.currentNovel !== null

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 8

                Button {
                    text: "Continue"
                    font.family: detailView.fontBody; font.pixelSize: 12; font.bold: true
                    contentItem: StyledText {
                        text: parent.text; font: parent.font
                        color: Appearance.m3colors.m3onPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { color: Appearance.m3colors.m3primary; radius: 14; opacity: parent.enabled ? 1 : 0.6 }
                    onClicked: continueReading()
                }

                Button {
                    text: "Next Chapter"
                    font.family: detailView.fontBody; font.pixelSize: 12; font.bold: true
                    contentItem: StyledText {
                        text: parent.text; font: parent.font
                        color: Appearance.m3colors.m3onPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { color: Appearance.m3colors.m3primary; radius: 14; opacity: parent.enabled ? 1 : 0.6 }
                    onClicked: readNext()
                }
                Item { Layout.fillWidth: true } // the buttons sit together on the left
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.3
            }
        }

        // ── Search & Sort bar ─────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 56
            color: Appearance.colors.colLayer1
            visible: ReaderNovel.currentNovel !== null

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 8

                // Search pill
                Rectangle {
                    Layout.fillWidth: true
                    height: 36; radius: 18
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: chapterSearch.activeFocus
                        ? Appearance.m3colors.m3primary
                        : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.2)
                    Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(130) } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 4 }
                        spacing: 6

                        StyledText {
                            text: "⌕"; font.pixelSize: 16
                            color: Appearance.m3colors.m3primary; opacity: 0.7
                        }

                        TextInput {
                            id: chapterSearch
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            font.family: detailView.fontBody; font.pixelSize: 12
                            color: Appearance.m3colors.m3onSurface
                            selectionColor: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.35)
                            clip: true

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Filter chapters…"
                                font.family: detailView.fontBody; font.pixelSize: 12
                                color: Appearance.m3colors.m3onSurfaceVariant; opacity: 0.45
                                visible: chapterSearch.text === "" && !chapterSearch.activeFocus
                            }

                            onTextChanged: detailView._chapterFilter = text
                        }

                        // Clear button
                        Item {
                            width: visible ? 28 : 0; height: 28
                            visible: detailView._chapterFilter !== ""

                            Rectangle {
                                anchors.centerIn: parent; width: 22; height: 22; radius: 11
                                color: clearArea.containsMouse
                                    ? ColorUtils.transparentize(Appearance.m3colors.m3onSurface, 0.12)
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(100) } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "✕"; font.pixelSize: 11; color: Appearance.m3colors.m3onSurfaceVariant
                            }
                            MouseArea {
                                id: clearArea; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    detailView._chapterFilter = ""
                                    chapterSearch.text = ""
                                }
                            }
                        }
                    }
                }

                // Sort toggle
                Item {
                    width: 36; height: 36

                    Rectangle {
                        anchors.fill: parent; radius: 18
                        color: sortArea.containsMouse
                            ? Appearance.m3colors.m3primaryContainer
                            : ColorUtils.transparentize(Appearance.m3colors.m3primaryContainer, 0.6)
                        border.color: Appearance.m3colors.m3primary; border.width: 1
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(130) } }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: detailView._sortAscending ? "↑" : "↓"
                        font.pixelSize: 16; font.bold: true
                        color: Appearance.m3colors.m3onPrimaryContainer
                    }
                    MouseArea {
                        id: sortArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: detailView._sortAscending = !detailView._sortAscending

                        ToolTip.visible: containsMouse
                        ToolTip.delay: 600
                        ToolTip.text: detailView._sortAscending ? "Sort: Ascending" : "Sort: Descending"
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.3
            }
        }

        // ── Chapter list ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // (no backdrop: the panel shows through)

            // Loading overlay
            SkeletonList {
                anchors.fill: parent; z: 5
                active: ReaderNovel.isFetchingDetail
                rowHeight: 62
                subtitle: false
            }

            // Error state (the backend or the site refused the novel)
            Rectangle {
                anchors.fill: parent; z: 4
                color: Appearance.colors.colLayer0Base
                visible: ReaderNovel.detailError.length > 0 && !ReaderNovel.isFetchingDetail

                Column {
                    anchors.centerIn: parent; spacing: 12

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "⚠"; font.pixelSize: 30; color: Appearance.m3colors.m3error; opacity: 0.8
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 280; horizontalAlignment: Text.AlignHCenter
                        text: "Couldn't load this novel\n" + ReaderNovel.detailError
                        color: Appearance.m3colors.m3onSurfaceVariant
                        font.family: detailView.fontBody; font.pixelSize: 12
                        wrapMode: Text.Wrap; lineHeight: 1.4
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: retryLabel.implicitWidth + 32; height: 32
                        radius: 16
                        color: retryArea.containsMouse ? Appearance.m3colors.m3primary : Appearance.m3colors.m3primaryContainer
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(130) } }

                        Text {
                            id: retryLabel; anchors.centerIn: parent
                            text: "Retry"
                            font.family: detailView.fontBody; font.pixelSize: 12; font.bold: true
                            color: retryArea.containsMouse ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onPrimaryContainer
                        }
                        MouseArea {
                            id: retryArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: ReaderNovel.retryDetail()
                        }
                    }
                }
            }

            ListView {
                ReaderWheel {}
                id: chapterList
                anchors.fill: parent; clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: detailView._processedChapters   // ← filtered + sorted

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: 3; color: Appearance.m3colors.m3primary; opacity: 0.45; radius: 2 }
                }

                delegate: ClickableRect {
                    id: rowAreaRect
                    width: chapterList.width; height: 62

                    readonly property var _libEntry: ReaderNovel.currentNovel
                        ? ReaderNovel.getLibraryEntry(ReaderNovel.currentNovel.id) : null
                    readonly property bool isLastRead:
                        _libEntry !== null && _libEntry !== undefined
                        && _libEntry.lastReadChapterId === modelData.id

                    color: isLastRead
                        ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.07)
                        : (rowAreaRect.pressed ? Appearance.colors.colLayer3
                            : (rowAreaRect.hovered ? Appearance.colors.colLayer2 : "transparent"))
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(110) } }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 72; rightMargin: 16 }
                        height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.25
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 14

                        // Chapter pill
                        Rectangle {
                            width: chPillTxt.implicitWidth + 16; height: 26; radius: 13
                            color: isLastRead ? Appearance.m3colors.m3primary : Appearance.m3colors.m3primaryContainer

                            StyledText {
                                id: chPillTxt; anchors.centerIn: parent
                                text: "Ch." + detailView.formatChapter(modelData.chapter)
                                font.family: detailView.fontBody; font.pixelSize: 9
                                font.bold: true; font.letterSpacing: 0.5
                                color: isLastRead ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onPrimaryContainer
                            }
                        }

                        Column {
                            Layout.fillWidth: true; spacing: 3

                            StyledText {
                                width: parent.width
                                text: modelData.title || ("Chapter " + detailView.formatChapter(modelData.chapter))
                                font.family: detailView.fontBody; font.pixelSize: 12
                                color: Appearance.m3colors.m3onSurface; elide: Text.ElideRight
                            }

                            StyledText {
                                visible: false
                                font.family: detailView.fontBody; font.pixelSize: 10
                                color: Appearance.m3colors.m3onSurfaceVariant; opacity: 0.5; font.letterSpacing: 0.3
                            }
                        }

                        Text {
                            text: "›"; font.pixelSize: 20; color: Appearance.m3colors.m3outline
                            opacity: rowAreaRect.hovered ? 0.9 : 0.4
                            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(120) } }
                        }
                    }

                    onClicked: {
                            ReaderNovel.fetchChapter(modelData.id)
                            detailView.chapterSelected(modelData.id)
                            if (ReaderNovel.currentNovel && ReaderNovel.isInLibrary(ReaderNovel.currentNovel.id))
                                ReaderNovel.updateLastRead(ReaderNovel.currentNovel.id, modelData.id, modelData.chapter)
                        }
                }
            }
        }
    }
}
