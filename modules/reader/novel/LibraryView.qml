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

    signal novelSelected(string novelId)

    // (no backdrop of its own: the panel's SurfaceMaterial shows through)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: ReaderNovel.libraryList.length === 0 && ReaderNovel.libraryLoaded

            EmptyState {
                title: "Your library is empty"
                subtitle: "Open any novel and tap  + Library"
                displayFont: libraryView.fontDisplay
                bodyFont: libraryView.fontBody
            }
        }


        SkeletonGrid {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !ReaderNovel.libraryLoaded
            active: !ReaderNovel.libraryLoaded
            padding: 8
            ratio: 1.72
            footerHeight: 30
        }

        GridView {
            ReaderWheel {}
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: ReaderNovel.libraryList.length > 0
            topMargin: 10; leftMargin: 8; rightMargin: 8; bottomMargin: 10
            cellWidth: Math.floor((width - leftMargin - rightMargin) / 4)
            cellHeight: cellWidth * 1.72
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: ReaderNovel.libraryList

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: Appearance.m3colors.m3primary; opacity: 0.45; radius: 2 }
            }

            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                CoverCard {
                    anchors.fill: parent
                    source: Reader.image(modelData.coverUrl)
                    title: modelData.title || ""
                    bodyFont: libraryView.fontBody
                    gradientHeight: 52
                    footerHeight: 30

                    CoverProgressBar {
                        height: 30
                        rowSpacing: 6
                        bodyFont: libraryView.fontBody
                        started: modelData.lastReadChapterNum
                        label: modelData.lastReadChapterNum
                                ? "Ch. " + modelData.lastReadChapterNum
                                : "Not started"
                    }

                    onClicked: {
                        ReaderNovel.fetchNovelDetail(modelData.id)
                        libraryView.novelSelected(modelData.id)
                    }
                }
            }
        }
    }
}
