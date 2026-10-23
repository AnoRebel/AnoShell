import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One placed widget: its card (unless the manifest says frame: false) and
 * its QML, loaded from the registry. A widget that's missing, broken or
 * fails to load shows why in its place; the others are unaffected.
 *
 * The widget's root item gets `ctx` (live, screenName, cell) and `settings`
 * (the placed widget's settings over the manifest's defaults).
 */
Item {
    id: host
    property var placed // { uid, id, x, y, w, h, settings }
    property var ctx
    readonly property var entry: Widgets.entries[host.placed?.id ?? ""] ?? null
    readonly property var problems: Widgets.errorsOf(host.placed?.id ?? "")
    readonly property var settings: {
        const s = {}
        for (const d of host.entry?.settings ?? []) if (d.key) s[d.key] = d.default
        return Object.assign(s, host.placed?.settings ?? {})
    }

    Rectangle {
        anchors.fill: parent
        visible: !host.entry || host.entry.frame || loader.status !== Loader.Ready
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant ?? "transparent"
    }

    Loader {
        id: loader
        anchors.fill: parent
        anchors.margins: host.entry?.frame === false ? 0 : 12
        asynchronous: true
        active: host.problems.length === 0
        source: host.problems.length === 0 ? host.entry.url : ""
        onLoaded: {
            if (item.hasOwnProperty("ctx")) item.ctx = Qt.binding(() => host.ctx)
            if (item.hasOwnProperty("settings")) item.settings = Qt.binding(() => host.settings)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        visible: host.problems.length > 0 || loader.status === Loader.Error
        spacing: 4
        MaterialSymbol { text: "broken_image"; iconSize: 22; color: Appearance.colors.colError }
        StyledText {
            Layout.fillWidth: true; Layout.fillHeight: true
            wrapMode: Text.Wrap; elide: Text.ElideRight
            text: !host.entry ? `"${host.placed?.id}" isn't installed`
                : host.problems.length ? `${host.entry.name}: ${host.problems.join("; ")}`
                : `${host.entry.name} didn't load`
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
