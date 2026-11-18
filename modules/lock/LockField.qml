import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * The password field of the arranged lock screens (LockElements): always ready for typing, Enter submits,
 * Esc clears; a wrong password clears and shakes it. Without focus (another screen's field has it) it
 * mirrors that field's length as dots. Below it: fingerprint, error, Caps Lock and "Checking…".
 */
ColumnLayout {
    id: root
    property var ctx
    property bool miniature: false
    property alias input: passwordInput
    spacing: 8

    Connections {
        target: root.ctx
        function onFailed() { passwordInput.text = ""; shake.start() }
    }

    Rectangle {
        id: field
        Layout.fillWidth: true
        implicitHeight: 52
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)
        border.width: passwordInput.activeFocus ? 2 : 1
        border.color: (root.ctx?.error ?? "").length > 0 ? Appearance.colors.colError
            : (passwordInput.activeFocus ? Appearance.colors.colPrimary : Qt.rgba(1, 1, 1, 0.2))

        SequentialAnimation {
            id: shake
            loops: 3
            NumberAnimation { target: row; property: "anchors.horizontalCenterOffset"; to: -10; duration: AnimationConfig.scaledDuration(40) }
            NumberAnimation { target: row; property: "anchors.horizontalCenterOffset"; to: 10; duration: AnimationConfig.scaledDuration(80) }
            NumberAnimation { target: row; property: "anchors.horizontalCenterOffset"; to: 0; duration: AnimationConfig.scaledDuration(40) }
        }

        RowLayout {
            id: row
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 36
            spacing: 8
            MaterialSymbol { text: root.ctx?.busy ? "hourglass_top" : "lock"; iconSize: 20; color: "white"; opacity: 0.55 }
            TextInput {
                id: passwordInput
                Layout.fillWidth: true
                echoMode: TextInput.Password
                font.pixelSize: Appearance.font.pixelSize.normal
                readonly property bool mirroring: !activeFocus && (root.ctx?.typedLength ?? 0) > 0
                color: mirroring ? "transparent" : "white"
                focus: !root.miniature
                enabled: !root.miniature && !(root.ctx?.busy ?? false)
                verticalAlignment: TextInput.AlignVCenter
                onAccepted: root.ctx?.submit(text)
                onTextChanged: if (activeFocus || text.length === 0) root.ctx?.reportTyped(text.length)
                onActiveFocusChanged: if (activeFocus) root.ctx?.reportTyped(text.length)
                Keys.onEscapePressed: event => { passwordInput.text = ""; event.accepted = true }
                // A key held through a resume must not type or submit (faillock).
                Keys.onPressed: event => { if (event.isAutoRepeat && event.key !== Qt.Key_Backspace) event.accepted = true }
                Text {
                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                    text: "Password"; color: "white"; opacity: 0.35; font.pixelSize: Appearance.font.pixelSize.normal
                    visible: passwordInput.text.length === 0 && !passwordInput.mirroring
                }
                Text {
                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                    visible: passwordInput.mirroring
                    text: passwordInput.passwordCharacter.repeat(Math.min(root.ctx?.typedLength ?? 0, 64))
                    elide: Text.ElideLeft
                    color: "white"; font: passwordInput.font
                }
            }
            MaterialSymbol {
                text: "arrow_forward"; iconSize: 20; color: "white"
                visible: passwordInput.text.length > 0 && !(root.ctx?.busy ?? false)
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.ctx?.submit(passwordInput.text) }
            }
        }
    }

    // One line under the field: what's going on, most important first.
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        readonly property var fp: root.ctx?.fingerprint ?? null
        text: (root.ctx?.error ?? "") !== "" ? root.ctx.error
            : root.ctx?.busy ? "Checking…"
            : (root.ctx?.capsLock ?? false) ? "Caps Lock is on"
            : fp?.available ? (fp.message || (fp.state === "scanning" ? "Or touch the fingerprint reader" : ""))
            : ""
        color: (root.ctx?.error ?? "") !== "" || fp?.state === "fail" ? Appearance.colors.colError
            : (root.ctx?.capsLock ?? false) && !(root.ctx?.busy ?? false) ? Appearance.colors.colWarning : "white"
        opacity: 0.85
        font.pixelSize: Appearance.font.pixelSize.smallie
    }
}
