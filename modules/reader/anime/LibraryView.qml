import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.reader.components

Item {
    id: libraryView

    readonly property string fontDisplay: Appearance.font.family.title
    readonly property string fontBody:    Appearance.font.family.main

    signal animeSelected(var show)

    onVisibleChanged: if (visible) ReaderAnime.refreshLatest()

    // (no backdrop of its own: the panel's SurfaceMaterial shows through)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 52
            color: Appearance.m3colors.m3surfaceContainerLow; z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 18; rightMargin: 16 }

                Row {
                    spacing: 0; Layout.fillWidth: true

                    Text {
                        text: "A"; font.family: libraryView.fontDisplay
                        font.pixelSize: 22; font.letterSpacing: 1; color: Appearance.m3colors.m3primary
                    }
                    StyledText {
                        text: "nime Library"; font.family: libraryView.fontDisplay
                        font.pixelSize: 22; font.letterSpacing: 1
                        color: Appearance.m3colors.m3onSurface; opacity: 0.85
                    }
                }

                // Entry count badge
                Rectangle {
                    visible: ReaderAnime.libraryList.length > 0
                    height: 22; width: libCountText.implicitWidth + 16; radius: 11
                    color: Appearance.m3colors.m3surfaceContainer
                    border.color: Appearance.m3colors.m3outlineVariant; border.width: 1

                    StyledText {
                        id: libCountText; anchors.centerIn: parent
                        text: ReaderAnime.libraryList.length
                        font.family: libraryView.fontBody
                        font.pixelSize: 10; font.letterSpacing: 0.5
                        color: Appearance.m3colors.m3onSurfaceVariant
                    }
                }
            }
        }

        // ── Empty state ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: ReaderAnime.libraryList.length === 0 && ReaderAnime.libraryLoaded

            EmptyState {
                title: "Your library is empty"
                subtitle: "Open any anime and tap  + Library"
                displayFont: libraryView.fontDisplay
                bodyFont: libraryView.fontBody
            }
        }

        // ── Loading ───────────────────────────────────────────────────────────
        SkeletonGrid {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !ReaderAnime.libraryLoaded
            active: !ReaderAnime.libraryLoaded
            padding: 8
            ratio: 1.78
            footerHeight: 28
        }

        // ── Library grid ──────────────────────────────────────────────────────
        GridView {
            ReaderWheel {}
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: ReaderAnime.libraryList.length > 0
            topMargin: 10; leftMargin: 8; rightMargin: 8; bottomMargin: 10
            cellWidth: Math.floor((width - leftMargin - rightMargin) / 4)
            cellHeight: cellWidth * 1.78
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: ReaderAnime.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                readonly property var entry: modelData

                CoverCard {
                    anchors.fill: parent
                    source: entry.thumbnail || ""
                    title: entry.englishName || entry.name || ""
                    bodyFont: libraryView.fontBody
                    footerHeight: 28

                    // Score badge
                    Rectangle {
                        visible: entry.score !== null && entry.score !== undefined
                        anchors { top: parent.top; left: parent.left; topMargin: 8; leftMargin: 8 }
                        height: 20; radius: 10; width: libScoreText.implicitWidth + 12
                        color: Qt.rgba(0, 0, 0, 0.72)

                        StyledText {
                            id: libScoreText; anchors.centerIn: parent
                            text: entry.score ? "★ " + (entry.score).toFixed(1) : ""
                            font.family: libraryView.fontBody
                            font.pixelSize: 8; font.bold: true
                            color: Appearance.colors.colWarning
                        }
                    }

                    // A newer episode has aired than the last one watched (AniList)
                    Rectangle {
                        visible: ReaderAnime.hasNewEpisode(entry)
                        anchors { top: parent.top; left: parent.left; topMargin: 32; leftMargin: 8 }
                        height: 20; radius: 10; width: newText.implicitWidth + 12
                        color: Appearance.m3colors.m3primary
                        StyledText {
                            id: newText; anchors.centerIn: parent
                            text: "NEW · Ep. " + (ReaderAnime.latestAired[entry.id] ?? "")
                            font.family: libraryView.fontBody
                            font.pixelSize: 8; font.bold: true
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }

                    // Bookmark indicator
                    Rectangle {
                        visible: entry.bookmarked
                        anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                        width: 22; height: 22; radius: 11
                        color: Qt.rgba(0, 0, 0, 0.65)

                        Text {
                            anchors.centerIn: parent; text: "♥"
                            font.pixelSize: 9; color: Appearance.m3colors.m3primary
                        }
                    }

                    CoverProgressBar {
                        height: 28
                        rowSpacing: 5
                        bodyFont: libraryView.fontBody
                        started: entry.lastWatchedEpNum
                        label: entry.lastWatchedEpNum
                            ? "Ep. " + entry.lastWatchedEpNum
                            : "Not started"
                    }

                    onClicked: {
                        // Reconstruct a minimal show object for fetchAnimeDetail
                        libraryView.animeSelected({
                            id:          entry.id,
                            name:        entry.name,
                            englishName: entry.englishName,
                            nativeName:  entry.nativeName  || "",
                            thumbnail:   entry.thumbnail,
                            score:       entry.score,
                            type:        entry.type        || "",
                            episodeCount: entry.episodeCount || "",
                            availableEpisodes: entry.availableEpisodes || { sub: 0, dub: 0, raw: 0 },
                            season:      entry.season      || null
                        })
                    }
                }
            }
        }
    }
}
