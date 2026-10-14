import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "."

/**
 * Hover-popup showing live thumbnails of windows on the active workspace.
 * Anchored to the same screen edge as AnoSpot. Visible while the user
 * hovers AnoSpot's Workspace widget OR is hovering this popup itself
 * (so the cursor can travel between them without flicker).
 *
 * Click any thumbnail → focus that window.
 *
 * Compositor-agnostic: the window list comes from
 * CompositorService.windowsOnOutput(); each window renders via ScreencopyView (the same primitive overview/taskView use).
 */
Scope {
    id: root

    readonly property bool enabledFlag: Config.options?.anoSpot?.workspaceHoverPreview?.enable ?? true
    readonly property string spotPosition: Config.options?.anoSpot?.position ?? "top"
    readonly property bool spotIsVertical: spotPosition === "left" || spotPosition === "right"
    readonly property int thumbW: Config.options?.anoSpot?.workspaceHoverPreview?.thumbnailWidth ?? 180
    readonly property int thumbH: Config.options?.anoSpot?.workspaceHoverPreview?.thumbnailHeight ?? 110

    Variants {
        model: GlobalStates.anoSpotWorkspacePreviewOpen ? Quickshell.screens : []

        PanelWindow {
            id: previewWindow
            required property var modelData
            screen: modelData

            visible: GlobalStates.anoSpotWorkspacePreviewOpen
            color: "transparent"

            implicitWidth: Math.min(modelData.width - 32, contentRow.implicitWidth + 16)
            implicitHeight: contentRow.implicitHeight + 16

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:anospot:wspreview"
            WlrLayershell.layer: WlrLayer.Overlay

            // Anchor to the same edge as AnoSpot, offset further into the
            // screen so it doesn't overlap the pill.
            anchors {
                top: root.spotPosition === "top" || root.spotIsVertical
                bottom: root.spotPosition === "bottom" || root.spotIsVertical
                left: root.spotPosition === "left"
                right: root.spotPosition === "right"
            }
            margins {
                top: root.spotPosition === "top" ? 56 : 0
                bottom: root.spotPosition === "bottom" ? 56 : 0
                left: root.spotPosition === "left" ? 56 : 0
                right: root.spotPosition === "right" ? 56 : 0
            }

            // Windows on this screen's visible workspace, from the compositor
            // backend (which only tracks windows while a lease is held).
            readonly property var windowList: visible ? CompositorService.windowsOnOutput(modelData.name) : []
            onVisibleChanged: visible ? CompositorService.acquireWindows("anoSpotPreview")
                                      : CompositorService.releaseWindows("anoSpotPreview")

            function _activate(entry) {
                GlobalStates.anoSpotWorkspacePreviewOpen = false
                CompositorService.focusWindow(entry)
            }

            // Keep the popup open while the cursor is over it.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: GlobalStates.anoSpotWorkspacePreviewOpen = true
                onExited: closeDelayTimer.restart()
            }

            // Hover-grace timer — cursor passes that exit briefly without
            // a re-enter close the popup. Reset by any mouse-enter on the
            // popup body or the originating widget.
            Timer {
                id: closeDelayTimer
                interval: Config.options?.anoSpot?.workspaceHoverPreview?.closeDelayMs ?? 300
                repeat: false
                onTriggered: GlobalStates.anoSpotWorkspacePreviewOpen = false
            }

            // Card
            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: Appearance?.rounding.normal ?? 14
                color: Appearance?.colors.colLayer0 ?? "#1e1e2e"
                border.width: Appearance?.glassTokens?.borderWidth ?? 1
                border.color: Appearance?.glassTokens?.borderColor
                            ?? Appearance?.colors.colOutlineVariant ?? "#444"
                opacity: Appearance?.glassTokens?.opacity ?? 1

                RowLayout {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 8

                    // Empty state
                    StyledText {
                        visible: previewWindow.windowList.length === 0
                        text: "No windows on this workspace"
                        font.pixelSize: 11
                        opacity: 0.55
                    }

                    Repeater {
                        model: previewWindow.windowList

                        Item {
                            required property var modelData
                            implicitWidth: root.thumbW
                            implicitHeight: root.thumbH + 18

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 2

                                // Thumbnail
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.thumbH
                                    radius: 8

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: Appearance?.colors.colLayer1 ?? "#2b2930"
                                        border.width: thumbMa.containsMouse ? 2 : 1
                                        border.color: thumbMa.containsMouse
                                            ? (Appearance?.colors.colPrimary ?? "#a6e3a1")
                                            : (Appearance?.colors.colOutlineVariant ?? "#44444466")
                                        Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
                                    }

                                    Loader {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        active: !!modelData.toplevel
                                        sourceComponent: ScreencopyView {
                                            anchors.fill: parent
                                            captureSource: modelData.toplevel ?? null
                                            live: true
                                            paintCursor: false
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: parent.width; height: parent.height; radius: 8
                                                }
                                            }
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: !modelData.toplevel
                                        text: "preview_off"
                                        iconSize: 24
                                        opacity: 0.4
                                    }

                                    MouseArea {
                                        id: thumbMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: previewWindow._activate(modelData)
                                    }
                                }

                                // Title
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.title || modelData.appId || "(window)"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
