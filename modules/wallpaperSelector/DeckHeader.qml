import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// The deck's head: title and position, the source tabs (Local, Favourites,
// Wallhaven), the sort order, search, and the gear / live preview / peek /
// close buttons. Everything here acts through the deck.
Item {
    id: head
    required property Item deck
    readonly property alias searchField: searchInput

    height: 44 * deck.u

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12 * head.deck.u

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "style"
            fill: 1
            iconSize: 28 * head.deck.u
            color: head.deck.tint.accent
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            StyledText {
                text: "Wallpapers"
                font.pixelSize: (Appearance?.font.pixelSize.huge ?? 22) * head.deck.u
                font.weight: Font.Bold
                color: Qt.rgba(1, 1, 1, 1) // over the darkened head of any picture
            }
            StyledText {
                text: head.deck.count === 0 ? "" : (head.deck.currentIndex + 1) + " of " + head.deck.count
                    + (head.deck.online && Wallhaven.hasMorePages ? "+" : "")
                    + (head.deck.online ? "  ·  wallhaven.cc" : "  ·  " + ({ name: "by name", hue: "by colour", date: "newest first" })[head.deck.sort])
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * head.deck.u
                color: Qt.rgba(1, 1, 1, 0.72)
            }
        }
    }

    DeckSegments {
        deck: head.deck
        anchors.centerIn: parent
        options: [
            { key: "local", label: "Local", icon: "photo_library" },
            { key: "favourites", label: "Favourites", icon: "favorite", badge: Wallpapers.favourites.length },
            { key: "wallhaven", label: "Wallhaven", icon: "travel_explore" }
        ]
        value: head.deck.mode
        onPicked: key => head.deck.setMode(key)
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8 * head.deck.u

        // Reading colours (anod's first scan of new files).
        DeckGlass {
            deck: head.deck
            anchors.verticalCenter: parent.verticalCenter
            visible: !head.deck.online && Wallpapers.paletteScanning
            width: readingRow.implicitWidth + 24 * head.deck.u
            height: 40 * head.deck.u
            Row {
                id: readingRow
                anchors.centerIn: parent
                spacing: 8 * head.deck.u
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "palette"; iconSize: 16 * head.deck.u; color: head.deck.tint.accent }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Reading colours…"
                    font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * head.deck.u
                    color: head.deck.tint.muted
                }
            }
        }

        DeckSegments {
            deck: head.deck
            anchors.verticalCenter: parent.verticalCenter
            visible: !head.deck.online
            options: [
                { key: "name", label: "Name", icon: "sort_by_alpha" },
                { key: "hue", label: "Colour", icon: "palette" },
                { key: "date", label: "Newest", icon: "schedule" }
            ]
            value: head.deck.sort
            onPicked: key => head.deck.setSort(key)
        }

        DeckGlass {
            deck: head.deck
            anchors.verticalCenter: parent.verticalCenter
            width: 260 * head.deck.u
            height: 40 * head.deck.u
            border.color: searchInput.activeFocus ? head.deck.tint.accent : Qt.rgba(head.deck.tint.ink.r, head.deck.tint.ink.g, head.deck.tint.ink.b, 0.12)
            StyledTextInput {
                id: searchInput
                anchors { fill: parent; leftMargin: 16 * head.deck.u; rightMargin: 16 * head.deck.u }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: head.deck.tint.ink
                font.pixelSize: (Appearance?.font.pixelSize.smallie ?? 13) * head.deck.u
                // Local: filters as you type. Wallhaven: searches on Enter.
                onTextChanged: if (!head.deck.online) head.deck.query = text
                onAccepted: {
                    if (head.deck.online) Wallhaven.search(text)
                    head.deck.focusKeys()
                }
                Keys.onEscapePressed: head.deck.focusKeys()
            }
            StyledText {
                anchors { left: parent.left; leftMargin: 16 * head.deck.u; verticalCenter: parent.verticalCenter }
                visible: searchInput.text === ""
                text: head.deck.online ? "Search Wallhaven  ( / )" : "Filter by name  ( / )"
                font.pixelSize: (Appearance?.font.pixelSize.smallie ?? 13) * head.deck.u
                color: head.deck.tint.muted
            }
        }

        DeckButton { deck: head.deck; anchors.verticalCenter: parent.verticalCenter; icon: "settings"; toolTip: "Folder and Wallhaven key"; checked: head.deck.settingsOpen; onClicked: head.deck.setSettingsOpen(!head.deck.settingsOpen) }
        DeckButton {
            deck: head.deck
            anchors.verticalCenter: parent.verticalCenter
            visible: !head.deck.online && head.deck.hasMotion
            icon: head.deck.live ? "motion_photos_on" : "motion_photos_off"
            toolTip: "Live preview (V)"
            checked: head.deck.live
            onClicked: head.deck.toggleLive()
        }
        DeckButton { deck: head.deck; anchors.verticalCenter: parent.verticalCenter; icon: "visibility"; toolTip: "Peek (Space)"; onClicked: head.deck.togglePeek() }
        DeckButton { deck: head.deck; anchors.verticalCenter: parent.verticalCenter; icon: "close"; toolTip: "Close (Esc)"; onClicked: head.deck.close() }
    }
}
