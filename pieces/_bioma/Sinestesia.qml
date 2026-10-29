// Ported from Bioma (GPL-3.0), services/Sinestesia.qml.
pragma Singleton

import QtQuick
import Quickshell
import qs.services as Ano

// The sound leaving the machine, as bands.
//
// Bioma reads its own capture tool (tools/sinestesia-bands); AnoShell already
// runs one cava for every visualiser (services/SpectrumService.qml), and two
// captures of the same audio is the error Bioma's design warns about. So the
// band is AnoShell's spectrum, held through its reference count: nothing runs
// while nobody holds it.
//
// ponytail: SpectrumService is mono, so both wings show the same spectrum;
// a stereo cava mode in SpectrumService would give each wing its channel.
Singleton {
    id: root

    property var holders: []
    readonly property bool active: root.holders.length > 0

    function hold(owner, wanted) {
        const held = root.holders.indexOf(owner) >= 0;
        if (wanted && !held)
            root.holders = root.holders.concat([owner]);
        else if (!wanted && held)
            root.holders = root.holders.filter(h => h !== owner);
    }

    onActiveChanged: root.active ? Ano.SpectrumService.registerComponent("bioma-sinestesia")
                                 : Ano.SpectrumService.unregisterComponent("bioma-sinestesia")
    Component.onDestruction: Ano.SpectrumService.unregisterComponent("bioma-sinestesia")

    // How every band draws the sound: `bars`, `plasma`, `vesicles` or `eardrum`
    // (Band.qml).
    readonly property string effect: Config.get("sinestesia.effect", "bars")

    readonly property int bandCount: Ano.SpectrumService.barsCount
    readonly property var left: root.active ? Ano.SpectrumService.values : []
    readonly property var right: root.left
    readonly property real level: root.left.length > 0 ? Math.max(...root.left) : 0
    readonly property bool available: true

    // Folded by peak rather than by mean: a mean turns a snare into a shrug.
    function fold(source, into) {
        if (into <= 0 || !source || source.length === 0)
            return [];
        if (into >= source.length)
            return source;

        const out = new Array(into);
        for (let i = 0; i < into; i++) {
            const from = Math.floor(i * source.length / into);
            const to = Math.max(from + 1, Math.floor((i + 1) * source.length / into));
            let peak = 0;
            for (let b = from; b < to; b++)
                if (source[b] > peak)
                    peak = source[b];
            out[i] = peak;
        }
        return out;
    }
}
