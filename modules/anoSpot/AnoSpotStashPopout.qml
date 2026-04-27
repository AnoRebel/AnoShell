import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "root:"
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

/**
 * Popout panel anchored beneath/above the AnoSpot pill that lists items
 * staged in the AnoSpotStash. Per-item × removes; "Clear all" empties the
 * stash and closes the popout.
 *
 * Action buttons (LocalSend / Open / Copy path / Move / Reveal) are added
 * by a follow-up commit; this commit ships the stage + remove/clear UX
 * only.
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.anoSpotStashOpen
    readonly property string spotPosition: Config.options?.anoSpot?.position ?? "top"
    readonly property bool spotIsVertical: spotPosition === "left" || spotPosition === "right"

    // Auto-close when the stash empties.
    Connections {
        target: AnoSpotStash
        function onEmptyChanged() {
            if (AnoSpotStash.empty) GlobalStates.anoSpotStashOpen = false;
        }
    }

    Variants {
        model: root.open ? Quickshell.screens : []

        PanelWindow {
            id: popoutWindow
            required property var modelData
            screen: modelData

            visible: root.open
            color: "transparent"

            implicitWidth: 360
            implicitHeight: Math.min(420, headerCol.implicitHeight + grid.implicitHeight + footerRow.implicitHeight + 56)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:anospot:stash"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Anchor opposite the spot. If spot is top, popout drops down
            // from the top edge; if bottom, popout rises from the bottom.
            // For left/right spots we anchor to the same vertical edge.
            anchors {
                top: root.spotPosition === "top" || root.spotIsVertical
                bottom: root.spotPosition === "bottom" || root.spotIsVertical
                left: root.spotPosition === "left"
                right: root.spotPosition === "right"
            }
            margins {
                top: root.spotPosition === "top" ? 56 : 0  // clear the pill (~36px + gap)
                bottom: root.spotPosition === "bottom" ? 56 : 0
                left: root.spotPosition === "left" ? 56 : 0
                right: root.spotPosition === "right" ? 56 : 0
            }

            // Click-outside-to-close scrim. Layer-shell exclusionMode is
            // Ignore so we don't fight the bar; the scrim is invisible but
            // catches clicks anywhere outside the card.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: GlobalStates.anoSpotStashOpen = false
            }

            // The card itself
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: 360
                height: Math.min(420, headerCol.implicitHeight + grid.implicitHeight + footerRow.implicitHeight + 56)
                radius: Appearance?.rounding?.normal ?? 14
                color: Appearance?.colors?.colLayer0 ?? "#1e1e2e"
                border.width: 1
                border.color: Appearance?.colors?.colOutlineVariant ?? "#444"

                // Swallow clicks on the card so the scrim doesn't close it.
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // ─── Header: title + count + total size ───────────────
                    ColumnLayout {
                        id: headerCol
                        spacing: 2
                        Layout.fillWidth: true

                        RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: "inventory_2"
                                iconSize: 18
                                color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Stash"
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                            }
                            StyledText {
                                text: `${AnoSpotStash.count} ${AnoSpotStash.count === 1 ? "item" : "items"} · ${AnoSpotStash.totalSizeText}`
                                font.pixelSize: 11
                                opacity: 0.7
                                color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                            }
                        }
                    }

                    // ─── Item grid ────────────────────────────────────────
                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        cellWidth: 110
                        cellHeight: 100
                        clip: true
                        model: AnoSpotStash.items

                        delegate: Item {
                            id: cellRoot
                            width: grid.cellWidth - 6
                            height: grid.cellHeight - 6

                            required property string fileURL
                            required property string filePath
                            required property string name
                            required property bool isDir
                            required property string sizeText

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Appearance?.colors?.colLayer1 ?? "#2b2930"
                                border.width: 1
                                border.color: Appearance?.colors?.colOutlineVariant ?? "#44444466"

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 4

                                    // Thumbnail (image preview if it's an image, icon otherwise)
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 50

                                        Image {
                                            id: thumb
                                            anchors.fill: parent
                                            source: cellRoot.isDir ? "" : cellRoot.fileURL
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            visible: status === Image.Ready
                                            sourceSize.width: 200
                                            sourceSize.height: 100
                                        }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: !thumb.visible
                                            text: cellRoot.isDir ? "folder" : "draft"
                                            iconSize: 32
                                            color: Appearance?.colors?.colOnLayer0Subtle ?? "#a6adc8"
                                        }
                                    }

                                    // Filename (elided)
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cellRoot.name
                                        font.pixelSize: 10
                                        elide: Text.ElideMiddle
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                    }
                                    // Size
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: cellRoot.sizeText
                                        font.pixelSize: 9
                                        opacity: 0.6
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                    }
                                }

                                // Per-item × removal button (top-right corner)
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 2
                                    width: 18; height: 18
                                    radius: 9
                                    color: removeMa.containsMouse
                                        ? (Appearance?.colors?.colError ?? "#f38ba8")
                                        : Qt.rgba(0, 0, 0, 0.4)
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 12
                                        color: "#ffffff"
                                    }
                                    MouseArea {
                                        id: removeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: AnoSpotStash.remove(cellRoot.filePath)
                                    }
                                }
                            }
                        }
                    }

                    // ─── Footer: clear-all button ─────────────────────────
                    RowLayout {
                        id: footerRow
                        Layout.fillWidth: true
                        spacing: 8

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            implicitHeight: 32
                            buttonRadius: 8
                            colBackground: Appearance?.colors?.colLayer1 ?? "#2b2930"

                            contentItem: RowLayout {
                                spacing: 6
                                MaterialSymbol {
                                    text: "delete_sweep"
                                    iconSize: 16
                                    color: Appearance?.colors?.colError ?? "#f38ba8"
                                }
                                StyledText {
                                    text: "Clear all"
                                    font.pixelSize: 12
                                    color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
                                }
                            }
                            onClicked: AnoSpotStash.clear()
                        }
                    }
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) GlobalStates.anoSpotStashOpen = false;
            }
        }
    }
}
