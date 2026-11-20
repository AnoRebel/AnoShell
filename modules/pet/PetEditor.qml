import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "pet.js" as Pet

// The pet editor (Settings → Modules → Desktop Pet, and a right-click on the pet): kind, colours, size, sound and
// pointer following, saved at once, with a live preview; "Try" makes the preview and the desktop pet do a behaviour.
ColumnLayout {
    id: root
    spacing: 8
    readonly property var opts: Config.options?.pet ?? ({})
    readonly property string kind: Pet.kindOf(root.opts.kind)
    readonly property string preset: root.opts.colors?.[root.kind] ?? ""
    property bool showEnable: true

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 150
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        clip: true
        PetActor {
            id: actor
            kind: root.kind
            size: 110
            areaWidth: parent.width
            floors: [{ id: "ground", x1: 0, x2: parent.width, y: parent.height - 8 }]
            x0: parent.width / 2; y0: parent.height - 8
            live: root.visible
            soundOn: root.opts.sound ?? false
        }
        PetRig {
            x: actor.x0 - width / 2; y: actor.y0 - height
            size: actor.size
            kind: root.kind; preset: root.preset
            p: actor.p; facing: actor.facing; t: actor.clock
            say: actor.say; hearts: actor.hearts
        }
    }

    ConfigSwitch {
        visible: root.showEnable
        label: "Show the pet on the desktop"
        configKey: "pet.enable"
        checked: root.opts.enable ?? false
        onCheckedChanged: Config.setNestedValue("pet.enable", checked)
    }
    ChoiceRow {
        Layout.fillWidth: true
        model: [{ value: "duck", label: "Duck", icon: "egg" }, { value: "cat", label: "Cat", icon: "pets" },
                { value: "dog", label: "Dog", icon: "sound_detection_dog_barking" }]
        current: root.kind
        onChose: v => Config.setNestedValue("pet.kind", v)
    }
    ChoiceRow {
        Layout.fillWidth: true
        model: Pet.presetNames(root.kind).map(n => ({ value: n, label: Pet.presetOf(root.kind, n).label, icon: "palette" }))
        current: Pet.presetNames(root.kind).includes(root.preset) ? root.preset : Pet.presetNames(root.kind)[0]
        onChose: v => Config.setNestedValue(`pet.colors.${root.kind}`, v)
    }
    ConfigSlider {
        label: "Size"
        configKey: "pet.size"
        from: 64; to: 256; stepSize: 8
        value: root.opts.size ?? 128
        onValueChanged: Config.setNestedValue("pet.size", Math.round(value))
        valueText: `${Math.round(value)} px`
    }
    ConfigSwitch {
        label: "Sounds"
        configKey: "pet.sound"
        checked: root.opts.sound ?? false
        onCheckedChanged: Config.setNestedValue("pet.sound", checked)
    }
    ConfigRow {
        label: "Where it's drawn"
        configKey: "pet.layer"
        sublabel: (root.opts.layer ?? "above") === "below" ? "Behind every window, on the desktop (it doesn't climb windows then)"
            : (root.opts.layer ?? "above") === "auto" ? "Over windows; behind them while a panel covers it, a window is maximised over it or one is being moved"
            : "Over windows; never over the shell's panels"
        ChoiceRow {
            model: [{ value: "above", label: "Above", icon: "flip_to_front" }, { value: "below", label: "Below", icon: "flip_to_back" },
                    { value: "auto", label: "Auto", icon: "auto_mode" }]
            current: root.opts.layer ?? "above"
            onChose: value => Config.setNestedValue("pet.layer", value)
        }
    }
    ConfigSwitch {
        label: "Now and then, walk to the pointer"
        configKey: "pet.chase"
        visible: CompositorService.supports.cursorPos ?? false
        checked: root.opts.chase ?? true
        onCheckedChanged: Config.setNestedValue("pet.chase", checked)
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: (CompositorService.supports.windowGeometry ? "It also walks on the tops of windows. " : "It walks along the bottom of the screen (this compositor doesn't report where windows are). ")
            + (CompositorService.supports.cursorPos ? "" : "This compositor doesn't report the pointer, so it can't follow it. ")
            + "Click its head to pet it; drag its body to carry it and let go to drop or throw it. Sounds stay off while Do not disturb is on."
    }
    StyledText { text: "Try"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
    ChoiceRow {
        Layout.fillWidth: true
        model: Pet.behaviours(root.kind).concat(["happy"]).map(b => ({ value: b, label: b.charAt(0).toUpperCase() + b.slice(1), icon: Pet.ICONS[b] ?? "pets" }))
        current: actor.behaviour
        onChose: v => { actor.act(v); GlobalStates.petAction(v) }
    }
}
