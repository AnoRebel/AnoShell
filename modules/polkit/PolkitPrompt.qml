import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The polkit password prompt (services/PolkitAuth.qml): on the screen that
 * had focus when the request came, over a dimmed (and, with polkit.blur,
 * blurred) screen. Enter authenticates, Esc or Cancel tells the app "no".
 * Details shows what polkit lets an agent know: the action (pkaction) and,
 * for pkexec, the waiting command line and what started it.
 */
Scope {
    id: root

    property string screenName: ""
    Connections {
        target: PolkitAuth
        function onAskingChanged() { if (PolkitAuth.asking) root.screenName = GlobalStates.focusedScreenName }
    }

    LazyLoader {
        active: PolkitAuth.asking && PolkitAuth.flow !== null

        PanelWindow {
            id: win
            readonly property var flow: PolkitAuth.flow
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Qt.rgba(0, 0, 0, 0.35)
            // The blur is the compositor's, per namespace: the bundled configs
            // leave quickshell:polkitPlain unblurred.
            WlrLayershell.namespace: (Config.options?.polkit?.blur ?? true) ? "quickshell:polkit" : "quickshell:polkitPlain"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // Window-wide: while polkit checks a password the field is
            // disabled and nothing in the window holds focus for Keys handlers.
            Shortcut { sequence: "Escape"; autoRepeat: false; onActivated: PolkitAuth.cancel() }

            // ── Details, read when first shown ──
            property bool showDetails: false
            property var action: ({})        // pkaction --verbose fields
            property string pkexecCommand: ""
            property string requestedBy: ""
            // The action runs a program through pkexec (its own exec action, or
            // an app action annotated with the program's path).
            readonly property bool _viaPkexec: win.flow?.actionId === "org.freedesktop.policykit.exec"
                || (win.action.annotation ?? "").includes("org.freedesktop.policykit.exec.path")
            onShowDetailsChanged: if (showDetails && !actionProc.ran) {
                actionProc.ran = true
                actionProc.command = ["pkaction", "--verbose", "--action-id", win.flow?.actionId ?? ""]
                actionProc.running = true
                pkexecProc.running = true
            }
            Process {
                id: actionProc
                property bool ran: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        const out = {}
                        for (const line of text.split("\n")) {
                            const m = line.match(/^\s+([a-z_ ]+):\s+(.*)$/)
                            if (m) out[m[1].trim()] = (out[m[1].trim()] ? out[m[1].trim()] + "\n" : "") + m[2].trim()
                        }
                        win.action = out
                    }
                }
            }
            // ponytail: polkit gives agents no request details, so the newest
            // pkexec process stands in for "the command"; exact while one waits.
            Process {
                id: pkexecProc
                command: ["sh", "-c", 'p=$(pgrep -n -x pkexec) || exit 0; tr "\\0" " " < /proc/$p/cmdline; echo; ps -o comm= -p "$(ps -o ppid= -p "$p" | tr -d " ")"']
                stdout: StdioCollector {
                    onStreamFinished: {
                        const l = text.split("\n")
                        win.pkexecCommand = (l[0] ?? "").trim()
                        win.requestedBy = (l[1] ?? "").trim()
                    }
                }
            }

            function authenticate() {
                if (!field.text.length || !win.flow?.isResponseRequired) return
                PolkitAuth.submit(field.text)
                field.text = ""
            }

            SurfaceMaterial {
                id: card
                surface: "polkit"
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 48)
                height: col.implicitHeight + 40
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 12

                    RowLayout {
                        spacing: 12
                        Rectangle {
                            implicitWidth: 44; implicitHeight: 44; radius: 22
                            color: Appearance.colors.colPrimaryContainer
                            Image {
                                id: actionIcon
                                anchors.centerIn: parent
                                width: 26; height: 26
                                sourceSize: Qt.size(26, 26)
                                visible: status === Image.Ready
                                source: win.flow?.iconName ? `image://icon/${win.flow.iconName}` : ""
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: !actionIcon.visible
                                text: "admin_panel_settings"; iconSize: 22
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: "Authentication required"
                                font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: win.flow?.message ?? ""
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // Who authenticates: chips when polkit offers more than one.
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: (win.flow?.identities?.length ?? 0) > 1
                        Repeater {
                            model: win.flow?.identities ?? []
                            RippleButton {
                                required property var modelData
                                implicitHeight: 30
                                buttonRadius: height / 2
                                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                                toggled: win.flow?.selectedIdentity === modelData
                                buttonText: `${modelData.isGroup ? "Group " : ""}${modelData.displayName || modelData.string}`
                                onClicked: win.flow.selectedIdentity = modelData
                            }
                        }
                    }
                    StyledText {
                        visible: (win.flow?.identities?.length ?? 0) === 1
                        text: `As ${win.flow?.selectedIdentity?.displayName || win.flow?.selectedIdentity?.string || ""}`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        border.width: field.activeFocus ? 2 : 0
                        border.color: win.flow?.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                        opacity: win.flow?.isResponseRequired ? 1 : 0.5
                        TextInput {
                            id: field
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            focus: true
                            enabled: win.flow?.isResponseRequired ?? false
                            echoMode: win.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                            color: Appearance.colors.colOnLayer2
                            selectionColor: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.normal
                            clip: true
                            Keys.onReturnPressed: win.authenticate()
                            Keys.onEnterPressed: win.authenticate()
                            onEnabledChanged: if (enabled) forceActiveFocus()
                            Component.onCompleted: forceActiveFocus()
                        }
                        StyledText {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            visible: field.text.length === 0
                            text: (win.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || "Password"
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        implicitHeight: 28
                        buttonText: win.showDetails ? "Hide details" : "Details"
                        onClicked: win.showDetails = !win.showDetails
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: win.showDetails
                        spacing: 4
                        Repeater {
                            model: [
                                ["Action", win.flow?.actionId ?? ""],
                                ["What", win.action.description ?? ""],
                                ["From", win.action.vendor ?? ""],
                                ["Command", win._viaPkexec ? win.pkexecCommand : ""],
                                ["Started by", win._viaPkexec ? win.requestedBy : ""],
                                ["Program", win.action.annotation ?? ""],
                            ].filter(r => r[1])
                            delegate: Item {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: detailRow.implicitHeight
                                RowLayout {
                                    id: detailRow
                                    width: parent.width
                                    spacing: 12
                                    StyledText {
                                        Layout.preferredWidth: 76
                                        Layout.alignment: Qt.AlignTop
                                        text: modelData[0]
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData[1]
                                        wrapMode: Text.WrapAnywhere
                                        font.family: Appearance.font.family.mono
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                            }
                        }
                    }

                    // polkit's own notes (e.g. "Swipe your finger"), or the failure.
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        visible: text.length > 0
                        text: win.flow?.supplementaryMessage || (win.flow?.failed ? "That didn't work. Try again." : "")
                        color: (win.flow?.supplementaryIsError || win.flow?.failed) ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        RippleButton { buttonText: "Cancel"; onClicked: PolkitAuth.cancel() }
                        RippleButton {
                            buttonText: "Authenticate"
                            toggled: true // the primary action
                            enabled: field.text.length > 0 && (win.flow?.isResponseRequired ?? false)
                            onClicked: win.authenticate()
                        }
                    }
                }
            }
        }
    }
}
