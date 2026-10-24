import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.reader.components

Item {
    id: readerView
    // Set by the panel: this reader is the one being read (its stack is on it).
    property bool active: true

    // ── Exposed API ──────────────────────────────────────────────────────────
    readonly property string fontDisplay: Appearance.font.family.title
    readonly property string fontBody:    Appearance.font.family.main

    // Emitted when the user navigates back
    signal backRequested()

    // ── Internal state ───────────────────────────────────────────────────────
    property bool headerVisible: true

    // Called by the parent to reset state when re-entering this view
    function reset() {
        headerVisible = true
    }

    // ── Ink-black background ─────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#08080a" }

    // ── Reader header ────────────────────────────────────────────────────────
    Rectangle {
        id: readerHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 54
        color: Qt.rgba(0.05, 0.05, 0.08, 0.95)
        z: 10
        opacity: readerView.headerVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

        // Bottom hairline
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 6; rightMargin: 16 }
            spacing: 2

            // Back button
            Item {
                width: 44; height: 44

                Rectangle {
                    anchors.centerIn: parent
                    width: 34; height: 34; radius: 17
                    color: readerBackArea.containsMouse
                        ? Qt.rgba(1, 1, 1, 0.1)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(130) } }
                }
                StyledText {
                    anchors.centerIn: parent
                    text: "←"
                    font.pixelSize: 18
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
                MouseArea {
                    id: readerBackArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        ReaderManga.clearChapterPages()
                        readerView.backRequested()
                    }
                }
            }

            // Title
            StyledText {
                Layout.fillWidth: true
                text: ReaderManga.currentManga ? ReaderManga.currentManga.title : ""
                font.family: readerView.fontDisplay
                font.pixelSize: 13
                color: Qt.rgba(1, 1, 1, 0.85)
                elide: Text.ElideRight
            }

            // Page counter badge
            Rectangle {
                visible: ReaderManga.chapterPages.length > 0
                height: 24
                width: pageCountText.implicitWidth + 18
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.09)
                border.color: Qt.rgba(1, 1, 1, 0.12)
                border.width: 1

                StyledText {
                    id: pageCountText
                    anchors.centerIn: parent
                    text: (pageListView.visiblePage + 1) + " / " + ReaderManga.chapterPages.length
                    font.family: readerView.fontBody
                    font.pixelSize: 10
                    font.letterSpacing: 0.5
                    color: Qt.rgba(1, 1, 1, 0.65)
                }
            }
        }
    }

    // ── Fetching pages overlay ───────────────────────────────────────────────
    LoadingState {
        anchors.fill: parent
        z: 8
        active: ReaderManga.isFetchingPages
        color: "#08080a"
        textColor: "white"
        spinnerSize: 40
        label: "loading pages"
        detail: ReaderManga.currentManga ? ReaderManga.currentManga.title : ""
        bodyFont: readerView.fontBody
    }

    // ── Pages error overlay ──────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#08080a"
        visible: ReaderManga.pagesError.length > 0 && !ReaderManga.isFetchingPages
        z: 7

        Column {
            anchors.centerIn: parent
            spacing: 10

            StyledText {
                text: "⚠"
                font.pixelSize: 32
                color: Appearance.m3colors.m3error
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.85
            }
            StyledText {
                text: ReaderManga.pagesError
                color: Qt.rgba(1, 1, 1, 0.45)
                font.pixelSize: 11
                font.family: readerView.fontBody
                wrapMode: Text.Wrap
                width: 260
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
            }
        }
    }

    // ── Page list ────────────────────────────────────────────────────────────
    ListView {
        ReaderWheel {}
        id: pageListView
        anchors {
            fill: parent
            topMargin: readerView.headerVisible ? 54 : 0
        }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Both tabs have a reader on the same chapter; only the one on screen builds pages.
        model: readerView.active ? ReaderManga.chapterPages : []
        spacing: 3
        // The page at the middle of the view (currentIndex doesn't follow scrolling).
        readonly property int visiblePage: Math.max(0, indexAt(width / 2, contentY + height / 2))
        Behavior on anchors.topMargin { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

        // Tap anywhere to toggle header
        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            onClicked: {
                readerView.headerVisible = !readerView.headerVisible
                mouse.accepted = false
            }
        }

        delegate: Item {
            width: pageListView.width
            height: pageImg.implicitHeight > 0
                ? pageImg.implicitHeight * (pageListView.width / pageImg.implicitWidth)
                : pageListView.width * 1.42

            Image {
                id: pageImg
                anchors.fill: parent
                source: modelData.url || ""
                // Decoded at the strip's width, not the scan's (often 2–4× wider).
                sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false // pages scrolled away are released, not kept decoded
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(350) } }

            }

            // Loading placeholder. Beside the page, not inside it: the page
            // sits at opacity 0 until it's ready, which would hide a child.
            Rectangle {
                anchors.fill: parent
                z: -1
                color: "#111115"
                visible: pageImg.status !== Image.Ready

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Spinner {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: pageImg.status !== Image.Error
                        width: 22
                        border.width: 2
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        arcColor: Qt.rgba(1, 1, 1, 0.45)
                        period: 1200
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: pageImg.status === Image.Error
                        text: "⊘"
                        font.pixelSize: 22
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "p. " + (modelData.index + 1)
                            + (pageImg.status === Image.Error ? "  ·  failed to load" : "")
                        color: Qt.rgba(1, 1, 1, 0.3)
                        font.pixelSize: 10
                        font.family: readerView.fontBody
                        font.letterSpacing: 1.5
                    }

                    // Download progress, once the image reports any
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: pageImg.status === Image.Loading && pageImg.progress > 0
                        width: 96; height: 2; radius: 1
                        color: Qt.rgba(1, 1, 1, 0.08)

                        Rectangle {
                            width: parent.width * pageImg.progress
                            height: parent.height; radius: 1
                            color: Appearance.m3colors.m3primary
                            Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(160) } }
                        }
                    }
                }
            }
        }

        ScrollBar.vertical: StyledScrollBar {
            thickness: 2
            handleOpacity: 0.35
            handleRadius: 1
        }
    }

    // ── Reading progress bar (bottom) ─────────────────────────────────────────
    Item {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 3
        z: 9
        visible: ReaderManga.chapterPages.length > 0

        // Track
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(1, 1, 1, 0.06)
        }

        // Fill
        Rectangle {
            width: ReaderManga.chapterPages.length > 0
                ? parent.width * ((pageListView.visiblePage + 1) / ReaderManga.chapterPages.length)
                : 0
            height: parent.height
            color: Appearance.m3colors.m3primary
            Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
        }
    }
}
