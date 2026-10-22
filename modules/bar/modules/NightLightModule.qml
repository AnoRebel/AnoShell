import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

/**
 * Night light toggle (bar/pill module "nightlight"): click toggles
 * services/NightLight's "on now", scroll warms or cools the night
 * temperature. A running schedule shows as an outlined moon.
 */
Item {
    id: root
    implicitWidth: icon.implicitWidth + 8
    implicitHeight: Appearance.sizes.barHeight

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        // filled: on now; outline in the accent: a schedule is running
        text: NightLight.enabled || NightLight.scheduled ? "nightlight" : "wb_sunny"
        iconSize: Appearance?.font.pixelSize.larger ?? 20
        fill: NightLight.enabled ? 1 : 0
        color: NightLight.enabled || NightLight.scheduled
            ? Appearance?.colors.colPrimary ?? "#65558F"
            : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: NightLight.toggle()
        onWheel: event => {
            if (event.angleDelta.y === 0) return
            const t = NightLight.nightTemp + (event.angleDelta.y > 0 ? -100 : 100)
            Config.setNestedValue("nightLight.nightTemp", Math.max(2500, Math.min(6500, t)))
        }
        StyledToolTip {
            text: NightLight.enabled ? `Night light on, ${NightLight.nightTemp}K (click to turn off, scroll to adjust)`
                : NightLight.scheduled ? `Night light automatic, ${NightLight.scheduleText} (click to turn on now, scroll to set how warm)`
                : "Night light off (click to warm the screen, scroll to set how warm)"
        }
    }
}
