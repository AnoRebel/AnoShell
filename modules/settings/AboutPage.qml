import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import "root:modules/common"
import "root:modules/common/widgets"
import "root:modules/common/functions"
import "root:services"

/**
 * About page with elaborate user profile card (avatar + icon picker),
 * shell info, system details, and credits.
 */
ColumnLayout {
    id: root
    spacing: 16

    // ═══ User Profile ═══
    SettingsCard {
        icon: "person"
        title: "User Profile"
        subtitle: "Avatar, display name, and account settings"
        collapsible: false

        // Profile card with large avatar + greeting
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 140
            radius: Appearance?.rounding.normal ?? 12
            color: Appearance?.colors.colLayer2 ?? "#2B2930"
            clip: true

            // Subtle gradient overlay
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.12) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            RowLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 20

                // Avatar with change overlay
                Item {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 96

                    // Border ring
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 3
                        border.color: Appearance?.colors.colPrimary ?? "#65558F"
                    }

                    // Avatar image with circular clip
                    Item {
                        anchors.centerIn: parent
                        width: 86; height: 86

                        Rectangle {
                            id: avatarMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                        }

                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            source: `file://${Directories.userAvatarPathFace}`
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false // Don't cache so it updates when changed
                            sourceSize: Qt.size(192, 192)
                            visible: false

                            onStatusChanged: {
                                if (status === Image.Error) {
                                    if (String(source).indexOf(Directories.userAvatarPathAccountsService) >= 0)
                                        source = `file://${Directories.userAvatarPathFaceIcon}`
                                    else
                                        source = `file://${Directories.userAvatarPathAccountsService}`
                                }
                            }
                        }

                        OpacityMask {
                            anchors.fill: parent
                            source: avatarImg
                            maskSource: avatarMask
                            visible: avatarImg.status === Image.Ready
                        }

                        // Fallback
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                            visible: avatarImg.status !== Image.Ready

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "person"
                                iconSize: 42
                                color: Appearance?.colors.colPrimary ?? "#65558F"
                            }
                        }
                    }

                    // Hover overlay for change
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#99000000"
                        opacity: avatarHover.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            MaterialSymbol { text: "photo_camera"; iconSize: 22; color: "white"; Layout.alignment: Qt.AlignHCenter }
                            StyledText { text: "Change"; font.pixelSize: 10; color: "white"; Layout.alignment: Qt.AlignHCenter }
                        }
                    }

                    MouseArea {
                        id: avatarHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: avatarPicker.running = true
                    }
                }

                // Greeting + user info
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: {
                            const hour = new Date().getHours()
                            if (hour < 5) return "Good Night"
                            if (hour < 12) return "Good Morning"
                            if (hour < 18) return "Good Afternoon"
                            return "Good Evening"
                        }
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        color: Appearance?.colors.colPrimary ?? "#65558F"
                    }
                    StyledText {
                        text: Quickshell.env("USER") || "user"
                        font.pixelSize: Appearance?.font.pixelSize.huger ?? 28
                        font.weight: Font.Bold
                        font.capitalization: Font.Capitalize
                    }
                    StyledText {
                        text: `${Quickshell.env("HOSTNAME") || "localhost"} • ${CompositorService.compositor}`
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        opacity: 0.5
                    }
                }

                // Quick action buttons
                ColumnLayout {
                    spacing: 4
                    ToolbarButton { iconName: "lock"; iconSize: 20; toolTipText: "Lock screen"; onClicked: Quickshell.execDetached(["loginctl", "lock-session"]) }
                    ToolbarButton { iconName: "manage_accounts"; iconSize: 20; toolTipText: "Manage account"; onClicked: Quickshell.execDetached(["xdg-open", "settings://users"]) }
                }
            }
        }

        // Avatar file picker process (uses zenity)
        Process {
            id: avatarPicker
            command: ["zenity", "--file-selection", "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.bmp", "--title=Choose Avatar Image"]
            stdout: StdioCollector {
                id: avatarPickerOutput
                onStreamFinished: {
                    const path = avatarPickerOutput.text.trim()
                    if (path.length > 0) {
                        avatarCopyProc.command = ["bash", "-c", `cp '${path}' ~/.face && cp '${path}' ~/.face.icon`]
                        avatarCopyProc.running = true
                    }
                }
            }
        }

        Process {
            id: avatarCopyProc
            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0) {
                    // Force reload by toggling source
                    avatarImg.source = ""
                    avatarImg.source = `file://${Directories.userAvatarPathFace}`
                    Quickshell.execDetached(["notify-send", "Avatar Updated", "Your profile picture has been changed", "-a", "Ano Shell"])
                }
            }
        }

        // Custom avatar path override
        ConfigRow {
            label: "Custom avatar path"
            sublabel: "Override ~/.face with a custom path (leave empty for default)"
            StyledTextInput {
                text: Config.options?.user?.avatarPath ?? ""
                onEditingFinished: Config.setNestedValue("user.avatarPath", text)
                Layout.fillWidth: true
                font.family: Appearance?.font.family.mono ?? "monospace"
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            }
        }
    }

    // ═══ Shell Info ═══
    SettingsCard {
        icon: "terminal"
        title: "Ano Shell"
        subtitle: "A comprehensive QuickShell desktop shell"
        collapsible: false

        // Logo area
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            Layout.alignment: Qt.AlignHCenter

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol { text: "terminal"; iconSize: 48; color: Appearance?.colors.colPrimary ?? "#65558F"; Layout.alignment: Qt.AlignHCenter }
                StyledText {
                    text: "Ano Shell"
                    font.pixelSize: Appearance?.font.pixelSize.huger ?? 24
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // ═══ System Details ═══
    SettingsCard {
        icon: "computer"
        title: "System Details"
        subtitle: "Runtime environment and paths"

        Repeater {
            model: [
                { label: "Compositor", value: CompositorService.compositor },
                { label: "Shell root", value: Directories.shellRoot },
                { label: "Config file", value: Directories.shellConfigPath },
                { label: "Uptime", value: DateTime.uptime },
                { label: "User", value: Quickshell.env("USER") || "unknown" },
                { label: "Hostname", value: Quickshell.env("HOSTNAME") || Quickshell.env("HOST") || "localhost" },
                { label: "Desktop", value: Quickshell.env("XDG_CURRENT_DESKTOP") || "unknown" },
                { label: "Session", value: Quickshell.env("XDG_SESSION_TYPE") || "unknown" },
            ]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 12
                StyledText {
                    text: modelData.label
                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                    opacity: 0.5
                    Layout.preferredWidth: 100
                }
                StyledText {
                    text: modelData.value
                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                    font.family: Appearance?.font.family.mono ?? "monospace"
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }
        }
    }

    // ═══ Features ═══
    SettingsCard {
        icon: "star"
        title: "Features"
        subtitle: "What this shell can do"

        GridLayout {
            Layout.fillWidth: true
            columns: 2; columnSpacing: 12; rowSpacing: 8

            Repeater {
                model: [
                    { icon: "dock_to_bottom", text: "Multi-bar on any edge" },
                    { icon: "overview", text: "10 overview layouts" },
                    { icon: "neurology", text: "AI Chat (3 providers)" },
                    { icon: "notifications", text: "Persistent notifications" },
                    { icon: "palette", text: "Material You theming" },
                    { icon: "image", text: "Wallpaper rotation" },
                    { icon: "bluetooth_connected", text: "Bluetooth + WiFi" },
                    { icon: "music_note", text: "MPRIS media controls" },
                    { icon: "keyboard", text: "XKB layout indicator" },
                    { icon: "monitor_heart", text: "System resource monitor" },
                    { icon: "thermostat", text: "Weather + GPS" },
                    { icon: "settings", text: "Full settings GUI" },
                ]

                RowLayout {
                    required property var modelData
                    spacing: 6
                    MaterialSymbol { text: modelData.icon; iconSize: 16; color: Appearance?.colors.colPrimary ?? "#65558F" }
                    StyledText { text: modelData.text; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12 }
                }
            }
        }
    }

    // ═══ Credits ═══
    SettingsCard {
        icon: "groups"
        title: "Credits & Sources"
        subtitle: "Built from patterns across the QuickShell community"

        Repeater {
            model: [
                { name: "@rebels (end-4)", desc: "Base architecture, MD3 theme, panel families" },
                { name: "@hyprview", desc: "10 workspace overview layout algorithms" },
                { name: "@inir", desc: "Compositor detection, Niri IPC, enhanced panels" },
                { name: "@ilyamiro", desc: "Weather, media, battery, network widget designs" },
                { name: "@caelestia", desc: "Animation system patterns" },
                { name: "@noctalia-shell", desc: "Settings module patterns" },
                { name: "@end-4 (ii)", desc: "AI chat service and sidebar integration" },
            ]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 12
                Rectangle {
                    width: 6; height: 6; radius: 3
                    color: Appearance?.colors.colPrimary ?? "#65558F"
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 6
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText { text: modelData.name; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; font.weight: Font.DemiBold }
                    StyledText { text: modelData.desc; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12; opacity: 0.5; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
        }
    }
}
