import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

// The deck's gear: the wallpaper folder (background.wallpaperDir; Wallhaven
// downloads land there too) and the Wallhaven API key. The key is written by
// anod to $XDG_DATA_HOME/anoshell/secrets/wallhaven (0600) and never shown
// again; the field only takes a new one.
DeckGlass {
    id: card
    signal closeRequested

    property string keyStatus: ""   // message under the key field

    function reset() {
        folderField.text = Wallpapers.effectiveDirectory.replace(FileUtils.trimFileProtocol(Directories.home), "~")
        keyField.text = ""
        card.keyStatus = ""
        folderField.forceActiveFocus()
        folderField.selectAll()
    }
    function applyFolder() {
        // Shown resolved (the default included); cleared = back to the default.
        const typed = folderField.text.trim().replace(/\/+$/, "")
        if (typed !== Wallpapers.effectiveDirectory.replace(FileUtils.trimFileProtocol(Directories.home), "~"))
            Config.setNestedValue("background.wallpaperDir", typed)
    }
    function saveKey(value) {
        card.keyStatus = "Saving…"
        Wallhaven.setApiKey(value, err => {
            card.keyStatus = err !== "" ? err : value.trim() === "" ? "Key removed" : "Key saved"
            if (err === "") keyField.text = ""
        })
    }

    width: 380 * deck.u
    height: col.implicitHeight + 32 * deck.u
    radius: (Appearance?.rounding.normal ?? 17) * deck.u
    color: Qt.rgba(deck.tint.surface.r, deck.tint.surface.g, deck.tint.surface.b, 0.94)

    // Clicks inside don't reach the deck behind.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }

    Column {
        id: col
        x: 16 * card.deck.u; y: 16 * card.deck.u
        width: parent.width - 32 * card.deck.u
        spacing: 8 * card.deck.u

        component Label: StyledText {
            font.pixelSize: (Appearance?.font.pixelSize.smallie ?? 13) * card.deck.u
            font.weight: Font.DemiBold
            color: card.deck.tint.ink
        }
        component Note: StyledText {
            width: col.width
            wrapMode: Text.Wrap
            font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * card.deck.u
            color: card.deck.tint.muted
        }
        component Field: Rectangle {
            default property alias content: holder.data
            width: col.width
            height: 36 * card.deck.u
            radius: height / 2
            color: Qt.rgba(card.deck.tint.ink.r, card.deck.tint.ink.g, card.deck.tint.ink.b, 0.07)
            border.width: 1
            border.color: Qt.rgba(card.deck.tint.ink.r, card.deck.tint.ink.g, card.deck.tint.ink.b, 0.14)
            Item { id: holder; anchors { fill: parent; leftMargin: 14 * card.deck.u; rightMargin: 14 * card.deck.u } }
        }

        Label { text: "Wallpaper folder" }
        Field {
            StyledTextInput {
                id: folderField
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: Appearance?.font.family.mono ?? "monospace"
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * card.deck.u
                color: card.deck.tint.ink
                onAccepted: card.applyFolder()
                Keys.onEscapePressed: card.closeRequested()
            }
        }
        Note { text: "Enter applies. Wallhaven downloads are saved here too." }

        Item { width: 1; height: 4 * card.deck.u }
        Label { text: "Wallhaven API key" + (Wallhaven.hasKey ? "  ·  set" : "") }
        Field {
            StyledTextInput {
                id: keyField
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                echoMode: TextInput.Password
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * card.deck.u
                color: card.deck.tint.ink
                onAccepted: if (text.trim() !== "") card.saveKey(text)
                Keys.onEscapePressed: card.closeRequested()
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: keyField.text === ""
                text: Wallhaven.hasKey ? "Paste a new key to replace it" : "Paste your key (wallhaven.cc → Settings → Account)"
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * card.deck.u
                color: card.deck.tint.muted
            }
        }
        Row {
            spacing: 8 * card.deck.u
            DeckButton { deck: card.deck; icon: "save"; toolTip: "Save the key"; visible: keyField.text.trim() !== ""; onClicked: card.saveKey(keyField.text) }
            DeckButton { deck: card.deck; icon: "delete"; toolTip: "Remove the saved key"; visible: Wallhaven.hasKey; onClicked: card.saveKey("") }
        }
        Note {
            text: card.keyStatus !== "" ? card.keyStatus
                : "Optional: unlocks NSFW results and your account's filters. Kept in ~/.local/share/anoshell/secrets/wallhaven (only you can read it), never in config.json."
        }
    }
}
