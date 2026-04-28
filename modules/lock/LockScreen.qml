import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Lock screen — only active on Niri (Hyprland uses hyprlock).
 * Uses PAM authentication for password verification.
 * Shows user avatar, time, date, and a password input field.
 * Configurable: enable/disable, compositor-aware.
 */
Scope {
    id: root

    // Only run on Niri — Hyprland uses hyprlock
    readonly property bool lockEnabled: CompositorService.compositor === "niri" && (Config.options?.lock?.enable ?? true)

    Loader {
        active: root.lockEnabled

        sourceComponent: Scope {
            id: lockScope

            Connections {
                target: GlobalStates
                function onScreenLockedChanged() {
                    if (GlobalStates.screenLocked) pamContext.start()
                }
            }

            PamContext {
                id: pamContext
                configDirectory: "login"

                onAuthenticationStarted: {
                    lockScope.authError = ""
                    lockScope.authenticating = true
                }
                onAuthenticated: {
                    lockScope.authenticating = false
                    GlobalStates.screenLocked = false
                }
                onAuthenticationError: (message) => {
                    lockScope.authError = message || "Authentication failed"
                    lockScope.authenticating = false
                    passwordInput.text = ""
                    errorShake.start()
                }
            }

            property string authError: ""
            property bool authenticating: false

            Variants {
                model: GlobalStates.screenLocked ? Quickshell.screens : []

                PanelWindow {
                    id: lockWindow
                    required property var modelData
                    screen: modelData
                    visible: GlobalStates.screenLocked
                    color: "transparent"
                    WlrLayershell.namespace: "quickshell:lock"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                    anchors { top: true; bottom: true; left: true; right: true }

                    // Background
                    Rectangle {
                        anchors.fill: parent
                        color: Appearance?.m3colors.m3background ?? "#1C1B1F"

                        // Wallpaper background (blurred)
                        Image {
                            anchors.fill: parent
                            source: {
                                const path = Config.options?.background?.wallpaperPath ?? ""
                                return path.length > 0 ? (path.startsWith("file://") ? path : "file://" + path) : ""
                            }
                            fillMode: Image.PreserveAspectCrop; visible: false
                            id: bgImage
                        }
                        ShaderEffectSource {
                            anchors.fill: parent
                            sourceItem: bgImage; visible: bgImage.status === Image.Ready
                            // Simple dim overlay since we can't use MultiEffect in lock
                        }
                        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
                    }

                    // Content
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 24; width: 320

                        // Clock
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter; spacing: 4
                            StyledText {
                                text: DateTime.time
                                font.pixelSize: 72; font.weight: Font.Bold
                                font.family: Appearance?.font.family.numbers ?? "monospace"
                                color: "white"; Layout.alignment: Qt.AlignHCenter
                            }
                            StyledText {
                                text: DateTime.collapsedCalendarFormat
                                font.pixelSize: 18; color: "white"; opacity: 0.6
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                        // Avatar
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 80; height: 80; radius: 40
                            color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                            border.width: 3; border.color: Appearance?.colors.colPrimary ?? "#65558F"
                            Image {
                                anchors.centerIn: parent; width: 72; height: 72
                                source: `file://${Directories.userAvatarPathFace}`
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                layer.enabled: true
                                layer.effect: OpacityMask { maskSource: Rectangle { width: 72; height: 72; radius: 36 } }
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent; text: "person"; iconSize: 40
                                color: Appearance?.colors.colPrimary ?? "#65558F"
                                visible: parent.children[0].status !== Image.Ready
                            }
                        }

                        // Username
                        StyledText {
                            text: Quickshell.env("USER") || "user"
                            font.pixelSize: 20; font.weight: Font.DemiBold
                            font.capitalization: Font.Capitalize
                            color: "white"; Layout.alignment: Qt.AlignHCenter
                        }

                        // Password input
                        Rectangle {
                            Layout.fillWidth: true; implicitHeight: 48; radius: 24
                            color: Qt.rgba(1, 1, 1, 0.1)
                            border.width: passwordInput.activeFocus ? 2 : 1
                            border.color: lockScope.authError.length > 0 ? "#EF5350" : (passwordInput.activeFocus ? Appearance?.colors.colPrimary ?? "#65558F" : "#33ffffff")

                            // Error shake animation
                            NumberAnimation {
                                id: errorShake; target: parent; property: "x"
                                from: parent.x - 10; to: parent.x + 10; duration: 80
                                loops: 3; easing.type: Easing.InOutQuad
                                onFinished: parent.x = 0
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }; spacing: 8
                                MaterialSymbol {
                                    text: lockScope.authenticating ? "hourglass_top" : "lock"
                                    iconSize: 20; color: "white"; opacity: 0.5
                                }
                                TextInput {
                                    id: passwordInput
                                    Layout.fillWidth: true
                                    echoMode: TextInput.Password
                                    font.pixelSize: 16; color: "white"
                                    focus: GlobalStates.screenLocked
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: !lockScope.authenticating
                                    onAccepted: {
                                        if (text.length > 0) {
                                            pamContext.respond(text)
                                        }
                                    }
                                    Text {
                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                        text: "Password"; color: "white"; opacity: 0.3; font.pixelSize: 16
                                        visible: !passwordInput.text || passwordInput.text.length === 0
                                    }
                                }
                                MaterialSymbol {
                                    text: "arrow_forward"; iconSize: 20; color: "white"
                                    visible: passwordInput.text?.length > 0 && !lockScope.authenticating
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (passwordInput.text.length > 0) pamContext.respond(passwordInput.text) }
                                    }
                                }
                            }
                        }

                        // Error message
                        StyledText {
                            text: lockScope.authError
                            visible: lockScope.authError.length > 0
                            font.pixelSize: 13; color: "#EF5350"
                            Layout.alignment: Qt.AlignHCenter
                        }

                        // Loading indicator
                        StyledText {
                            text: "Authenticating..."
                            visible: lockScope.authenticating
                            font.pixelSize: 13; color: "white"; opacity: 0.5
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { GlobalStates.screenLocked = true }
        function unlock(): void { /* handled by PAM */ }
    }
}
