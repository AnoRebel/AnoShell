import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.reader.components

Item {
    id: browseView

    readonly property string fontDisplay: Appearance.font.family.title
    readonly property string fontBody:    Appearance.font.family.main

    signal novelSelected(string novelId)

    property string currentFilter: "hot"

    function _switchFilter(f) {
        if (currentFilter === f) return
        currentFilter = f
        searchBar.visible = false
        searchField.text = ""
        ReaderNovel.clearNovelList()
        if (f === "hot") ReaderNovel.fetchHot()
        else             ReaderNovel.fetchLatest(true)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Top bar ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: Appearance.colors.colLayer1
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 18; rightMargin: 12 }
                spacing: 10

                // Title (hidden while search bar is open)
                Row {
                    spacing: 0
                    visible: !searchBar.visible
                    StyledText {
                        text: "N"
                        font.family: browseView.fontDisplay
                        font.pixelSize: 24; font.letterSpacing: 1
                        color: Appearance.m3colors.m3primary
                    }
                    StyledText {
                        text: "ovel"
                        font.family: browseView.fontDisplay
                        font.pixelSize: 24; font.letterSpacing: 1
                        color: Appearance.m3colors.m3onSurface; opacity: 0.85
                    }
                }

                // Search bar (shown when search icon is tapped)
                Rectangle {
                    id: searchBar
                    Layout.fillWidth: true
                    height: 38; radius: 19
                    color: Appearance.colors.colLayer2
                    visible: false
                    border.color: searchField.activeFocus ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                    border.width: searchField.activeFocus ? 1.5 : 1
                    Behavior on border.width { NumberAnimation { duration: AnimationConfig.scaledDuration(120) } }

                    TextInput {
                        id: searchField
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left; right: clearBtn.left
                            leftMargin: 16; rightMargin: 6
                        }
                        color: Appearance.m3colors.m3onSurface
                        font.family: browseView.fontBody; font.pixelSize: 13
                        clip: true
                        onTextChanged: searchDebounce.restart()
                        Keys.onEscapePressed: {
                            searchBar.visible = false
                            text = ""
                            browseView.currentFilter = "hot"
                            ReaderNovel.fetchHot()
                        }
                    }

                    StyledText {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16 }
                        text: "Search novels…"
                        color: Appearance.m3colors.m3onSurfaceVariant; font.family: browseView.fontBody
                        font.pixelSize: 13; visible: searchField.text.length === 0; opacity: 0.6
                    }

                    Item {
                        id: clearBtn
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
                        width: 22; height: 22
                        visible: searchField.text.length > 0
                        opacity: visible ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(100) } }
                        Rectangle {
                            anchors.centerIn: parent; width: 18; height: 18; radius: 9
                            color: Appearance.colors.colLayer4
                        }
                        StyledText {
                            anchors.centerIn: parent; text: "✕"
                            color: Appearance.m3colors.m3onSurfaceVariant; font.pixelSize: 9; font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: searchField.text = "" }
                    }
                }

                Timer {
                    id: searchDebounce
                    interval: 380
                    onTriggered: {
                        var q = searchField.text.trim()
                        if (q.length > 0) {
                            browseView.currentFilter = "search"
                            ReaderNovel.searchNovels(q, "", "All", true)
                        } else {
                            browseView.currentFilter = "hot"
                            ReaderNovel.fetchHot()
                        }
                    }
                }

                // ── Provider dropdown button ──────────────────────────────────
                Item {
                    visible: !searchBar.visible
                    width: 200
                    height: 32

                    Rectangle {
                        anchors.fill: parent; radius: 16
                        color: providerDropArea.containsMouse
                            ? Appearance.colors.colLayer4
                            : Appearance.colors.colLayer2
                        border.color: Appearance.m3colors.m3outlineVariant; border.width: 1
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(150) } }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        StyledText {
                            id: providerLabel
                            text: {
                                for (var i = 0; i < ReaderNovel.availableProviders.length; i++) {
                                    if (ReaderNovel.availableProviders[i].name === ReaderNovel.activeProvider)
                                        return ReaderNovel.availableProviders[i].label
                                }
                                return ReaderNovel.activeProvider
                            }
                            font.family: browseView.fontBody; font.pixelSize: 11
                            font.letterSpacing: 0.3
                            color: ReaderNovel.isSwitchingProvider ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(150) } }
                        }

                        // Tiny spinner shown while switching
                        Spinner {
                            visible: ReaderNovel.isSwitchingProvider
                            width: 10
                            border.width: 1.5
                            anchors.verticalCenter: parent.verticalCenter
                            period: 700
                            running: ReaderNovel.isSwitchingProvider
                        }

                        // Chevron (hidden while switching)
                        StyledText {
                            visible: !ReaderNovel.isSwitchingProvider
                            text: providerPopup.visible ? "▲" : "▾"
                            font.pixelSize: 8
                            color: Appearance.m3colors.m3onSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: providerDropArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!ReaderNovel.isSwitchingProvider)
                                providerPopup.visible = !providerPopup.visible
                        }
                    }

                    // ── Dropdown popup ────────────────────────────────────────
                    Rectangle {
                        id: providerPopup
                        visible: false
                        // Anchor below the button, right-aligned
                        anchors { top: parent.bottom; right: parent.right; topMargin: 6 }
                        width: 150
                        height: popupColumn.implicitHeight + 10
                        radius: 10
                        color: Appearance.colors.colLayer3
                        border.color: Appearance.m3colors.m3outlineVariant; border.width: 1
                        z: 100

                        // Drop shadow hint
                        layer.enabled: true

                        Column {
                            id: popupColumn
                            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 5 }
                            spacing: 0

                            Repeater {
                                model: ReaderNovel.availableProviders

                                delegate: Item {
                                    width: parent.width
                                    height: 36

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4; anchors.rightMargin: 4
                                        radius: 7
                                        color: {
                                            if (modelData.name === ReaderNovel.activeProvider)
                                                return Appearance.m3colors.m3primaryContainer
                                            return optionArea.containsMouse
                                                ? Appearance.colors.colLayer4
                                                : "transparent"
                                        }
                                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
                                    }

                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 14 }
                                        spacing: 8

                                        // Active indicator dot
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Appearance.m3colors.m3primary
                                            visible: modelData.name === ReaderNovel.activeProvider
                                        }
                                        // Spacer when not active so text stays aligned
                                        Item {
                                            width: 6; height: 6
                                            visible: modelData.name !== ReaderNovel.activeProvider
                                        }

                                        StyledText {
                                            text: modelData.label
                                            font.family: browseView.fontBody; font.pixelSize: 12
                                            color: modelData.name === ReaderNovel.activeProvider
                                                ? Appearance.m3colors.m3onPrimaryContainer
                                                : Appearance.m3colors.m3onSurface
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: optionArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            providerPopup.visible = false
                                            ReaderNovel.switchProvider(modelData.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Search icon ───────────────────────────────────────────────
                Item {
                    width: 40; height: 40

                    Rectangle {
                        anchors.centerIn: parent; width: 34; height: 34; radius: 17
                        color: searchBar.visible ? Appearance.m3colors.m3primaryContainer : "transparent"
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                    }
                    StyledText {
                        anchors.centerIn: parent; text: "⌕"; font.pixelSize: 19
                        color: searchBar.visible ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            searchBar.visible = !searchBar.visible
                            if (searchBar.visible) searchField.forceActiveFocus()
                            else {
                                searchField.text = ""
                                browseView.currentFilter = "hot"
                                ReaderNovel.fetchHot()
                            }
                        }
                    }
                }
            }
        }

        // ── Filter chips (Hot / Latest) ───────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 48
            color: Appearance.colors.colLayer1; clip: true

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.25
            }

            ListView {
                ReaderWheel {}
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                orientation: ListView.Horizontal; spacing: 7; clip: true
                boundsBehavior: Flickable.StopAtBounds

                model: ListModel {
                    ListElement { label: "Hot";    fid: "hot"    }
                    ListElement { label: "Latest"; fid: "latest" }
                }

                delegate: Item {
                    width: chip.implicitWidth + 28; height: parent.height

                    Rectangle {
                        id: chip
                        anchors.centerIn: parent
                        implicitWidth: chipLbl.implicitWidth + 28; height: 30; radius: 15
                        color: browseView.currentFilter === fid ? Appearance.m3colors.m3primary : Appearance.colors.colLayer2
                        border.color: browseView.currentFilter === fid ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }

                        StyledText {
                            id: chipLbl; anchors.centerIn: parent; text: label
                            font.family: browseView.fontBody; font.pixelSize: 12
                            font.letterSpacing: 0.6
                            color: browseView.currentFilter === fid ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurfaceVariant
                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: browseView._switchFilter(fid)
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.3
            }
        }

        // ── Novel grid ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // Close the provider popup when clicking outside it
            MouseArea {
                anchors.fill: parent
                enabled: providerPopup.visible
                onClicked: providerPopup.visible = false
                z: 50
            }

            // Loading overlay: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent; z: 10
                active: (ReaderNovel.isFetchingNovel || ReaderNovel.isSwitchingProvider)
                    && ReaderNovel.novelList.length === 0
                cellWidth: (width - 30) / 4
                ratio: 1.65
            }

            // More pages on the way
            LoadingBar {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 11
                active: ReaderNovel.isFetchingNovel && ReaderNovel.novelList.length > 0
            }

            // Error overlay
            Rectangle {
                anchors.fill: parent; color: Appearance.colors.colLayer0Base; z: 9
                visible: ReaderNovel.novelError.length > 0 && !ReaderNovel.isFetchingNovel

                Column {
                    anchors.centerIn: parent; spacing: 10
                    Text { text: "⚠"; font.pixelSize: 32; color: Appearance.m3colors.m3error; anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.8 }
                    Text {
                        text: ReaderNovel.novelError; color: Appearance.m3colors.m3onSurfaceVariant
                        font.pixelSize: 12; font.family: browseView.fontBody
                        wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                    }
                }
            }

            GridView {
                ReaderWheel {}
                id: novelGrid
                anchors.fill: parent; anchors.margins: 10
                cellWidth: (width - 10) / 4
                cellHeight: cellWidth * 1.65
                clip: true; boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: ReaderNovel.novelList }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: 3; color: Appearance.m3colors.m3primary; opacity: 0.45; radius: 2 }
                }

                onContentYChanged: {
                    if (contentY + height > contentHeight - cellHeight * 2)
                        ReaderNovel.fetchNextPage()
                }

                delegate: Item {
                    width: novelGrid.cellWidth; height: novelGrid.cellHeight

                    ClickableRect {
                        id: nCard
                        anchors { fill: parent; margins: 5 }
                        radius: 10; color: Appearance.colors.colLayer2; clip: true

                        CoverPlaceholder {
                            anchors.fill: coverImg
                            status: coverImg.status
                            glyphSize: 28
                        }

                        Image {
                            id: coverImg
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: parent.height - nTitleBar.height
                            source: modelData.coverUrl || ""
                            sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
                            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(300) } }

                            Rectangle {
                                visible: modelData.status && modelData.status.length > 0
                                anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                                height: 18; radius: 9; width: statusBadge.implicitWidth + 12
                                color: modelData.status === "Ongoing"
                                    ? Qt.rgba(0.2, 0.75, 0.4, 0.85)
                                    : Qt.rgba(0.3, 0.5, 0.9, 0.85)

                                Text {
                                    id: statusBadge; anchors.centerIn: parent
                                    text: (modelData.status || "").toUpperCase()
                                    font.family: browseView.fontBody; font.pixelSize: 7
                                    font.letterSpacing: 0.8; font.bold: true; color: "white"
                                }
                            }

                            Rectangle {
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                height: 52
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 1.0; color: Appearance.colors.colLayer2 }
                                }
                            }
                        }

                        Rectangle {
                            id: nTitleBar
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                            height: nTitleText.implicitHeight + 18; color: Appearance.colors.colLayer2; radius: 10

                            Column {
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 10; rightMargin: 10
                                }
                                spacing: 3

                                Text {
                                    id: nTitleText; width: parent.width
                                    text: modelData.title || ""
                                    font.family: browseView.fontBody; font.pixelSize: 11
                                    font.letterSpacing: 0.2; color: Appearance.m3colors.m3onSurface
                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 1.3
                                }
                                StyledText {
                                    visible: modelData.author && modelData.author.length > 0
                                    width: parent.width
                                    text: modelData.author || ""
                                    font.family: browseView.fontBody; font.pixelSize: 9
                                    color: Appearance.m3colors.m3onSurfaceVariant; opacity: 0.6
                                    elide: Text.ElideRight; font.letterSpacing: 0.3
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent; radius: 10; color: Appearance.m3colors.m3primary
                            opacity: nCard.pressed ? 0.16 : (nCard.hovered ? 0.07 : 0)
                            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(130) } }
                        }

                        transform: Scale {
                            origin.x: nCard.width / 2; origin.y: nCard.height / 2
                            xScale: nCard.pressed ? 0.97 : 1.0
                            yScale: nCard.pressed ? 0.97 : 1.0
                            Behavior on xScale { NumberAnimation { duration: AnimationConfig.scaledDuration(120); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                            Behavior on yScale { NumberAnimation { duration: AnimationConfig.scaledDuration(120); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                        }

                        onClicked: {
                                ReaderNovel.fetchNovelDetail(modelData.id)
                                browseView.novelSelected(modelData.id)
                            }
                    }
                }
            }
        }
    }
}
