pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

/**
 * System tray service with pinning support and smart filtering.
 */
Singleton {
    id: root

    property bool smartTray: Config.options.tray.filterPassive

    function getUniqueId(item) {
        return item.id + "::" + item.tooltipTitle
    }

    property list<var> itemsInUserList: SystemTray.items.values.filter(i =>
        Config.options.tray.pinnedItems.includes(getUniqueId(i)) && (!smartTray || i.status !== Status.Passive))
    property list<var> itemsNotInUserList: SystemTray.items.values.filter(i =>
        !Config.options.tray.pinnedItems.includes(getUniqueId(i)) && (!smartTray || i.status !== Status.Passive))

    property bool invertPins: Config.options.tray.invertPinnedItems
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    function getTooltipForItem(item) {
        let result = item.tooltipTitle.length > 0 ? item.tooltipTitle
            : (item.title.length > 0 ? item.title : item.id)
        if (item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription
        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]"
        return result
    }

    function pin(item) {
        const uniqueId = getUniqueId(item)
        const pins = Config.options.tray.pinnedItems
        if (pins.includes(uniqueId)) return
        Config.options.tray.pinnedItems.push(uniqueId)
    }

    function unpin(item) {
        const uniqueId = getUniqueId(item)
        Config.options.tray.pinnedItems = Config.options.tray.pinnedItems.filter(id => id !== uniqueId)
    }

    function isPinned(item) {
        return Config.options.tray.pinnedItems.includes(getUniqueId(item))
    }

    function togglePin(item) {
        const uniqueId = getUniqueId(item)
        if (Config.options.tray.pinnedItems.includes(uniqueId)) unpin(item)
        else pin(item)
    }
}
