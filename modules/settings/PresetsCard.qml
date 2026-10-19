import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * Presets: the bundled ones (ano/presets/) and yours
 * (~/.config/anoshell/presets/). Preview shows one live without writing
 * anything; Cancel puts everything back, Apply keeps it. Export saves the
 * settings you changed (no credentials) as a preset; Import copies a preset
 * file in.
 */
SettingsCard {
    id: card
    icon: "auto_awesome_mosaic"
    title: "Presets"
    subtitle: "Try a whole setup live, then keep it or go back"
    configKeys: []

    readonly property string bundledDir: Quickshell.shellPath("presets")
    readonly property string userDir: `${FileUtils.trimFileProtocol(Directories.config)}/anoshell/presets`
    property var presets: []           // { path, name, description, icon, values, mine }
    property string previewing: ""     // path of the preset being previewed
    property string message: ""
    property string importPath: ""

    function load() {
        lister.running = false
        lister.running = true
    }
    Component.onCompleted: load()
    Component.onDestruction: if (card.previewing !== "") Config.cancelPreview()

    // One line per preset file: path<TAB>json (names come in as arguments).
    Process {
        id: lister
        command: ["sh", "-c", 'for d in "$1" "$2"; do for f in "$d"/*.json; do [ -f "$f" ] && { printf "%s\\t" "$f"; tr -d "\\n" < "$f"; echo; }; done; done', "sh", card.bundledDir, card.userDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab < 0) continue
                    try {
                        const p = JSON.parse(line.slice(tab + 1))
                        if (!p || typeof p.values !== "object") continue
                        out.push({ path: line.slice(0, tab), name: p.name ?? "Preset", description: p.description ?? "",
                            icon: p.icon ?? "tune", values: p.values, mine: !line.startsWith(card.bundledDir) })
                    } catch (e) { console.warn(`[Presets] ${line.slice(0, tab)}: ${e}`) }
                }
                card.presets = out
            }
        }
    }

    function previewOne(p) {
        Config.preview(p.values)
        card.previewing = p.path
    }
    function cancel() {
        Config.cancelPreview()
        card.previewing = ""
    }
    function keep() {
        Config.commitPreview()
        card.previewing = ""
    }

    FileView { id: writer }
    // FileView doesn't create directories: make the presets dir, then write.
    property var _afterMkdir: null
    Process {
        id: mkdir
        command: ["mkdir", "-p", "--", card.userDir]
        onExited: { const f = card._afterMkdir; card._afterMkdir = null; if (f) f() }
    }
    function writeFile(path, text) {
        card._afterMkdir = () => { writer.path = path; writer.setText(text) }
        mkdir.running = true
    }
    function exportMine() {
        const d = new Date()
        const stamp = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}-${String(d.getHours()).padStart(2, "0")}${String(d.getMinutes()).padStart(2, "0")}`
        const preset = { name: `My setup ${stamp}`, description: "Exported from Settings", icon: "person", values: Config.exportValues() }
        const path = `${card.userDir}/my-setup-${stamp}.json`
        card.writeFile(path, JSON.stringify(preset, null, 2) + "\n")
        card.message = `Saved ${path} (${Object.keys(preset.values).length} settings)`
        reloadLater.restart()
    }
    Timer { id: reloadLater; interval: 300; onTriggered: card.load() }

    // Import: read the file, check it is a preset, copy it into your presets.
    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text)
                    if (!p || typeof p.values !== "object" || Array.isArray(p.values)) throw new Error("no \"values\" object")
                    const name = (card.importPath.split("/").pop() || "imported.json").replace(/[^A-Za-z0-9._-]/g, "_")
                    card.writeFile(`${card.userDir}/${name.endsWith(".json") ? name : name + ".json"}`, JSON.stringify(p, null, 2) + "\n")
                    card.message = `Imported "${p.name ?? name}"`
                    card.importPath = ""
                    reloadLater.restart()
                } catch (e) {
                    card.message = `Not a preset: ${e.message ?? e}`
                }
            }
        }
    }
    function importFile() {
        let p = card.importPath.trim()
        if (p.startsWith("~/")) p = Quickshell.env("HOME") + p.slice(1)
        reader.command = ["cat", "--", p]
        reader.running = true
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: card.presets
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: card.previewing === modelData.path
                width: 230
                height: col.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 4
                    RowLayout {
                        spacing: 6
                        MaterialSymbol { text: modelData.icon; iconSize: 20 }
                        StyledText { text: modelData.name; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                        StyledText { visible: modelData.mine; text: "yours"; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: modelData.description
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    RowLayout {
                        spacing: 6
                        RippleButton { visible: !active; buttonText: "Preview"; onClicked: card.previewOne(modelData) }
                        RippleButton { visible: active; toggled: true; buttonText: "Apply"; onClicked: card.keep() }
                        RippleButton { visible: active; buttonText: "Cancel"; onClicked: card.cancel() }
                    }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        RippleButton { buttonText: "Export my settings"; onClicked: card.exportMine() }
        ConfigTextInput {
            Layout.fillWidth: true
            placeholderText: "Import a preset file: ~/Downloads/preset.json"
            text: card.importPath
            onTextChanged: card.importPath = text
        }
        RippleButton { enabled: card.importPath.trim() !== ""; buttonText: "Import"; onClicked: card.importFile() }
    }
    StyledText {
        Layout.fillWidth: true
        visible: card.message !== ""
        wrapMode: Text.Wrap
        color: Appearance.colors.colSubtext
        text: card.message
    }
}
