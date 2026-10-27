import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.services
import qs.modules.reader.components

// Airing tab: this week's episodes, this season's shows and top airing shows
// from AniList (through anod). Picking one searches the anime source for it.
Item {
    id: airingView

    readonly property string fontDisplay: Appearance.font.family.title
    readonly property string fontBody: Appearance.font.family.main

    signal searchRequested(string title)

    onVisibleChanged: if (visible && ReaderAnime.airingItems.length === 0 && !ReaderAnime.airingLoading) ReaderAnime.fetchAiring()

    // "in 3 h" / "Tue 18:30"
    function when(t) {
        const d = new Date(t * 1000), mins = Math.round((d - Date.now()) / 60000)
        if (mins < 60) return mins <= 0 ? "now" : `in ${mins} min`
        if (mins < 24 * 60) return `in ${Math.round(mins / 60)} h`
        return Qt.formatDateTime(d, "ddd hh:mm")
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header: which list ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 52
            color: Appearance.colors.colLayer1; z: 2
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5
            }
            Row {
                anchors.centerIn: parent
                spacing: 6
                Repeater {
                    model: [{ id: "week", label: "This week" }, { id: "season", label: "This season" }, { id: "top", label: "Top airing" }]
                    ClickableRect {
                        required property var modelData
                        readonly property bool on: ReaderAnime.airingList === modelData.id
                        width: lbl.implicitWidth + 24; height: 30; radius: 15
                        color: on ? Appearance.m3colors.m3secondaryContainer
                            : (hovered ? Appearance.colors.colLayer2 : "transparent")
                        StyledText {
                            id: lbl; anchors.centerIn: parent
                            text: modelData.label
                            font.family: airingView.fontBody; font.pixelSize: 11
                            color: on ? Appearance.m3colors.m3onSecondaryContainer : Appearance.m3colors.m3onSurfaceVariant
                        }
                        onClicked: ReaderAnime.fetchAiring(modelData.id)
                    }
                }
            }
        }

        LoadingState {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: ReaderAnime.airingLoading && ReaderAnime.airingItems.length === 0
            active: visible
            label: "Asking AniList"
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !ReaderAnime.airingLoading && ReaderAnime.airingError.length > 0 && ReaderAnime.airingItems.length === 0
            EmptyState {
                title: "Couldn't load the list"
                subtitle: ReaderAnime.airingError + " · pick a list to retry"
            }
        }

        ListView {
            id: list
            ReaderWheel {}
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: ReaderAnime.airingItems.length > 0
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: ReaderAnime.airingItems
            ScrollBar.vertical: StyledScrollBar {}

            delegate: ClickableRect {
                id: row
                required property var modelData
                width: list.width; height: 76
                color: row.hovered ? Appearance.colors.colLayer2 : "transparent"
                onClicked: airingView.searchRequested(modelData.title)

                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 6; bottomMargin: 6 }
                    spacing: 12
                    Image {
                        Layout.preferredWidth: 46; Layout.fillHeight: true
                        source: ReaderAnime.proxied(row.modelData.cover)
                        sourceSize.width: 92
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            font.family: airingView.fontBody; font.pixelSize: 12; font.bold: true
                            color: Appearance.m3colors.m3onSurface; elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.airingAt
                                ? `Episode ${row.modelData.episode} · ${airingView.when(row.modelData.airingAt)}`
                                : [row.modelData.episodes ? `${row.modelData.episodes} episodes` : "",
                                   row.modelData.score ? `★ ${(row.modelData.score / 10).toFixed(1)}` : ""].filter(s => s).join(" · ")
                            font.family: airingView.fontBody; font.pixelSize: 10
                            color: Appearance.m3colors.m3onSurfaceVariant; elide: Text.ElideRight
                        }
                    }
                    StyledText {
                        text: "⌕"; font.pixelSize: 14
                        color: row.hovered ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outline
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.margins: 6
            horizontalAlignment: Text.AlignHCenter
            text: "Lists from AniList"
            font.pixelSize: 9; color: Appearance.m3colors.m3outline
        }
    }
}
