import QtQuick
import qs.modules.common
import qs.services

// A lock screen package (docs/lockscreens.md). It draws; the shell checks the
// password: call ctx.submit(text), clear the field on ctx.failed().
Item {
    id: root
    property var ctx

    Image {
        anchors.fill: parent
        source: root.ctx?.wallpaper ?? ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.15) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.75) }
        }
    }

    Column {
        anchors { left: parent.left; bottom: parent.bottom; margins: 64 }
        spacing: 8
        Text {
            text: DateTime.time
            color: "white"
            font { pixelSize: 112; weight: Font.Light; family: Appearance.font.family.numbers }
        }
        Text {
            text: DateTime.collapsedCalendarFormat
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: Appearance.font.pixelSize.larger
        }
        Item { width: 1; height: 24 }
        Row {
            spacing: 12
            Text {
                text: root.ctx?.busy ? "…" : "›"
                color: Appearance.colors.colPrimary
                font.pixelSize: 28
            }
            TextInput {
                id: field
                width: 360
                focus: true
                echoMode: TextInput.Password
                passwordCharacter: "•"
                color: "white"
                font.pixelSize: 24
                enabled: !(root.ctx?.busy ?? false)
                onAccepted: root.ctx?.submit(text)
                Keys.onPressed: event => { if (event.isAutoRepeat && event.key !== Qt.Key_Backspace) event.accepted = true } // a key held through resume must not type or submit (faillock)
                Text {
                    visible: field.text.length === 0
                    text: `Password for ${root.ctx?.user ?? ""}`
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.pixelSize: 24
                }
            }
        }
        Text {
            visible: text.length > 0
            text: root.ctx?.error || (root.ctx?.capsLock ? "Caps Lock is on" : "")
            color: root.ctx?.error ? Appearance.colors.colError : Appearance.colors.colWarning
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    Connections {
        target: root.ctx
        function onFailed() { field.text = "" }
    }
}
