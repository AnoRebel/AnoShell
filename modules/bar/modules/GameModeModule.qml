import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * GameMode / performance mode indicator — visible while a game holds
 * GameMode or performance mode is on. Available as bar module ID "gamemode".
 * Click: turn performance mode on or off (GameMode.toggle; turned off while
 * a game or a listed app holds it, it stays off until they are gone).
 *
 * Spec: ano-deferred-features-batch-2026 ▸ bar-status-indicators.
 */
Item {
    id: root

    visible: GameMode.active || GameMode.performance
    implicitWidth: visible ? row.implicitWidth + 12 : 0
    implicitHeight: Appearance.sizes.barHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            text: GameMode.active ? "videogame_asset" : "speed"
            iconSize: 16
            color: GameMode.performance
                ? (Appearance?.colors.colPrimary ?? "#a6e3a1")
                : (Appearance?.colors.colOnLayer1 ?? "#cdd6f4")
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: GameMode.toggle()
        StyledToolTip {
            text: {
                const game = GameMode.active
                    ? `Game mode active · ${GameMode.clientCount} client${GameMode.clientCount === 1 ? "" : "s"}` : ""
                const perf = GameMode.performance ? `Performance mode on: ${GameMode.performanceReason}`
                    : GameMode.refused ? "Performance mode off until the game or app closes" : "Performance mode off"
                return (game ? game + "\n" : "") + perf + " · click to turn " + (GameMode.performance ? "off" : "on")
            }
        }
    }
}
