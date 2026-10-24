import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.reader.components

Item {
    id: readerView

    readonly property string fontDisplay: Appearance.font.family.title
    readonly property string fontBody:    Appearance.font.family.reading

    signal backRequested()
    signal toggleFullscreen()

    property bool isFullscreen: false
    property real fontSize:      17
    property real lineHeight:    1.75
    property bool headerVisible: true

    function reset() {
        headerVisible = true
        textScroll.contentY = 0
    }

    readonly property bool _hasPrev: ReaderNovel.hasPrevChapter
    readonly property bool _hasNext: ReaderNovel.hasNextChapter

    Rectangle { anchors.fill: parent; color: "#1a1714" }

    Rectangle {
        id: readerHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 54; color: Qt.rgba(0.08, 0.07, 0.06, 0.97); z: 10
        opacity: readerView.headerVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1; color: Qt.rgba(1, 1, 1, 0.07)
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 6; rightMargin: 14 }
            spacing: 2

            Item {
                width: 44; height: 44
                Rectangle {
                    anchors.centerIn: parent; width: 34; height: 34; radius: 17
                    color: backHover.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(130) } }
                }
                Text { anchors.centerIn: parent; text: "←"; font.pixelSize: 18; color: Qt.rgba(1,1,1,0.7) }
                MouseArea {
                    id: backHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: { ReaderNovel.clearChapter(); readerView.backRequested() }
                }
            }

            Column {
                Layout.fillWidth: true; spacing: 1
                StyledText {
                    width: parent.width
                    text: ReaderNovel.currentNovel ? ReaderNovel.currentNovel.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: 11
                    color: Qt.rgba(1,1,1,0.45); elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: ReaderNovel.currentChapter ? ReaderNovel.currentChapter.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: 13
                    color: Qt.rgba(1,1,1,0.85); elide: Text.ElideRight
                }
            }

            Item {
                width: 34; height: 34
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: 15
                    color: fsMinusHover.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
                }
                Text { anchors.centerIn: parent; text: "A−"; font.pixelSize: 10; color: Qt.rgba(1,1,1,0.55) }
                MouseArea {
                    id: fsMinusHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: readerView.fontSize = Math.max(13, readerView.fontSize - 1)
                }
            }

            Item {
                width: 34; height: 34
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: 15
                    color: fsPlusHover.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
                }
                Text { anchors.centerIn: parent; text: "A+"; font.pixelSize: 11; color: Qt.rgba(1,1,1,0.55) }
                MouseArea {
                    id: fsPlusHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: readerView.fontSize = Math.min(26, readerView.fontSize + 1)
                }
            }

            Item {
                width: 34; height: 34
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: 15
                    color: fullscreenHover.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
                }
                Text {
                    anchors.centerIn: parent
                    text: readerView.isFullscreen ? "🗗" : "⛶"
                    font.pixelSize: 13; color: Qt.rgba(1,1,1,0.55)
                }
                MouseArea {
                    id: fullscreenHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: readerView.toggleFullscreen()
                }
            }

            Rectangle {
                visible: ReaderNovel.currentChapter !== null && ReaderNovel.currentChapter.wordCount > 0
                height: 24; width: wcTxt.implicitWidth + 18; radius: 12
                color: Qt.rgba(1,1,1,0.07); border.color: Qt.rgba(1,1,1,0.1); border.width: 1
                Text {
                    id: wcTxt; anchors.centerIn: parent
                    text: ReaderNovel.currentChapter !== null
                        ? (Math.round(ReaderNovel.currentChapter.wordCount / 100) / 10) + "k words" : ""
                    font.family: readerView.fontBody; font.pixelSize: 10
                    font.letterSpacing: 0.4; color: Qt.rgba(1,1,1,0.45)
                }
            }
        }
    }

    Item {
        anchors { top: readerHeader.bottom; left: parent.left; right: parent.right }
        height: 2; z: 9
        Rectangle { anchors.fill: parent; color: Qt.rgba(1,1,1,0.04) }
        Rectangle {
            width: textScroll.contentHeight > textScroll.height
                ? parent.width * Math.min(1,
                (textScroll.contentY + textScroll.height) / textScroll.contentHeight)
                : parent.width
            height: parent.height; color: Appearance.m3colors.m3primary
            Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(160); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
        }
    }

    // Loading: a ghost page in the reader's own measure and type size
    Rectangle {
        anchors.fill: parent; color: "#1a1714"; z: 8
        opacity: ReaderNovel.isFetchingChapter ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(280); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

        SkeletonText {
            anchors.fill: parent
            active: ReaderNovel.isFetchingChapter
            fontSize: readerView.fontSize
            lineHeight: readerView.lineHeight
            topInset: readerView.headerVisible ? 56 : 2
        }
    }

    LoadingBar {
        anchors { top: readerHeader.bottom; left: parent.left; right: parent.right }
        z: 10
        active: ReaderNovel.isFetchingChapter
    }

    Rectangle {
        anchors.fill: parent; color: "#1a1714"; z: 7
        visible: ReaderNovel.chapterError.length > 0 && !ReaderNovel.isFetchingChapter
        Column {
            anchors.centerIn: parent; spacing: 10
            Text {
                text: "⚠"; font.pixelSize: 32; color: Appearance.m3colors.m3error; opacity: 0.85
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: ReaderNovel.chapterError; color: Qt.rgba(1,1,1,0.4)
                font.pixelSize: 11; font.family: readerView.fontBody
                wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
            }
        }
    }

    Flickable {
        ReaderWheel {}
        id: textScroll
        anchors {
            fill: parent
            topMargin: readerView.headerVisible ? 56 : 2
            bottomMargin: 56
        }
        contentWidth: width
        contentHeight: textColumn.implicitHeight + 80
        clip: true; boundsBehavior: Flickable.StopAtBounds
        Behavior on anchors.topMargin { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

        MouseArea {
            anchors.fill: parent; propagateComposedEvents: true
            onClicked: { readerView.headerVisible = !readerView.headerVisible; mouse.accepted = false }
        }

        Column {
            id: textColumn
            width: Math.min(parent.width - 48, 720)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 36; bottomPadding: 48; spacing: 0

            StyledText {
                width: parent.width
                text: ReaderNovel.currentChapter ? ReaderNovel.currentChapter.title : ""
                font.family: readerView.fontDisplay
                font.pixelSize: readerView.fontSize + 7
                font.bold: true
                color: Qt.rgba(0.96, 0.93, 0.87, 0.90)
                wrapMode: Text.Wrap; lineHeight: 1.25; bottomPadding: 8
            }

            Item {
                width: parent.width; height: 24
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 5
                    Rectangle { width: 8;  height: 2; radius: 1; color: Appearance.m3colors.m3primary; opacity: 0.3 }
                    Rectangle { width: 32; height: 2; radius: 1; color: Appearance.m3colors.m3primary; opacity: 0.7 }
                    Rectangle { width: 8;  height: 2; radius: 1; color: Appearance.m3colors.m3primary; opacity: 0.3 }
                }
            }

            Item { width: 1; height: 20 }

            Repeater {
                model: ReaderNovel.currentChapter ? ReaderNovel.currentChapter.paragraphs : []
                StyledText {
                    width: textColumn.width
                    text: modelData
                    font.family: readerView.fontDisplay
                    font.pixelSize: readerView.fontSize
                    color: Qt.rgba(0.91, 0.87, 0.80, 0.87)
                    wrapMode: Text.Wrap; lineHeight: readerView.lineHeight
                    bottomPadding: Math.round(readerView.fontSize * readerView.lineHeight * 0.75)
                    textFormat: Text.PlainText
                }
            }
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle { implicitWidth: 2; color: Appearance.m3colors.m3primary; opacity: 0.25; radius: 1 }
        }
    }

    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 56; color: Qt.rgba(0.08, 0.07, 0.06, 0.97); z: 10

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 1; color: Qt.rgba(1,1,1,0.07)
        }

        Row {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }

            Item {
                width: parent.width / 3; height: parent.height
                opacity: readerView._hasPrev ? 1.0 : 0.25
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }

                Rectangle {
                    id: prevBtn
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left }
                    width: prevBtnRow.implicitWidth + 28; height: 36; radius: 18
                    color: prevNavArea.containsMouse && readerView._hasPrev
                        ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }

                    Row {
                        id: prevBtnRow; anchors.centerIn: parent; spacing: 5
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "‹"; font.pixelSize: 18; color: Qt.rgba(1,1,1,0.7) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Prev"; font.family: readerView.fontBody; font.pixelSize: 12; color: Qt.rgba(1,1,1,0.7) }
                    }
                }

                MouseArea {
                    id: prevNavArea; anchors.fill: parent; hoverEnabled: true
                    enabled: readerView._hasPrev
                    onClicked: { ReaderNovel.fetchPrevChapter(); textScroll.contentY = 0 }
                }
            }

            Item {
                width: parent.width / 3; height: parent.height
                StyledText {
                    anchors.centerIn: parent
                    text: ReaderNovel.currentChapter ? ReaderNovel.currentChapter.title : ""
                    font.family: readerView.fontBody; font.pixelSize: 10
                    color: Qt.rgba(1,1,1,0.28); font.letterSpacing: 0.4
                    elide: Text.ElideMiddle; width: parent.width - 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Item {
                width: parent.width / 3; height: parent.height
                opacity: readerView._hasNext ? 1.0 : 0.25
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }

                Rectangle {
                    id: nextBtn
                    anchors { verticalCenter: parent.verticalCenter; right: parent.right }
                    width: nextBtnRow.implicitWidth + 28; height: 36; radius: 18
                    color: nextNavArea.containsMouse && readerView._hasNext
                        ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.45)
                        : ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.22)
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }

                    Row {
                        id: nextBtnRow; anchors.centerIn: parent; spacing: 5
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Next"; font.family: readerView.fontBody; font.pixelSize: 12; color: Qt.rgba(1,1,1,0.92) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "›"; font.pixelSize: 18; color: Qt.rgba(1,1,1,0.92) }
                    }
                }

                MouseArea {
                    id: nextNavArea; anchors.fill: parent; hoverEnabled: true
                    enabled: readerView._hasNext
                    onClicked: { ReaderNovel.fetchNextChapter(); textScroll.contentY = 0 }
                }
            }
        }
    }
}
