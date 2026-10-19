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

    // Emitted when the user taps an entry — parent handles navigation
    signal mangaSelected(string mangaId)

    // ── Background ────────────────────────────────────────────────────────────
    // (no backdrop of its own: the panel's SurfaceMaterial shows through)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Empty state ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ReaderManga.libraryList.length === 0 && ReaderManga.libraryLoaded

            EmptyState {
                title: "Your library is empty"
                subtitle: "Open any manga and tap  + Library"
                displayFont: libraryView.fontDisplay
                bodyFont: libraryView.fontBody
            }
        }

        // ── Loading (first open before file is read) ──────────────────────────
        SkeletonGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !ReaderManga.libraryLoaded
            active: !ReaderManga.libraryLoaded
            padding: 8
            ratio: 1.72
            footerHeight: 30
        }

        GridView {
            ReaderWheel {}
            id: libGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: ReaderManga.libraryList.length > 0
            topMargin: 10
            leftMargin: 8
            rightMargin: 8
            bottomMargin: 10
            cellWidth: Math.floor((width - leftMargin - rightMargin) / 4)
            cellHeight: cellWidth * 1.72
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: ReaderManga.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                readonly property var libEntry: modelData

                CoverCard {
                    anchors.fill: parent
                    source: Reader.image(libEntry.coverUrl)
                    title: libEntry.title || ""
                    bodyFont: libraryView.fontBody
                    gradientHeight: 48
                    footerHeight: 30

                    CoverProgressBar {
                        height: 30
                        rowSpacing: 6
                        bodyFont: libraryView.fontBody
                        started: libEntry.lastReadChapterNum
                        label: libEntry.lastReadChapterNum
                                ? "Ch. " + libEntry.lastReadChapterNum
                                : "Not started"
                    }

                    onClicked: {
                        ReaderManga.fetchMangaDetail(libEntry.id)
                        libraryView.mangaSelected(libEntry.id)
                    }
                }
            }
        }
    }
}
