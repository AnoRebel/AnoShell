import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "lockLayout.js" as LockLayout

/**
 * A lock screen's arranged elements (lock.layouts; lockLayout.js): clock, avatar, user name, password
 * field, keyboard layout, battery, notifications and desktop pieces, each centred at its fractions of this
 * item, drawn at its natural size × scale × (height / 1080), turned and faded as set. Used by the built-in
 * lock screen once it's arranged, by Simple, and by the layout editor (`miniature`: nothing takes input).
 */
FocusScope {
    id: root
    property var ctx
    property var elements: []
    property bool miniature: false
    // Elements drawn as placeholders when they'd be empty (the editor: no battery, no notifications…).
    property bool showEmpty: root.miniature
    // The field's input, to focus or read (null without a field).
    property Item fieldInput: null

    Repeater {
        model: root.elements
        FocusScope {
            id: slot
            required property var modelData
            required property int index
            readonly property var piece: modelData.type === "piece" ? (Pieces.entries[modelData.settings?.id ?? ""] ?? null) : null
            readonly property var r: LockLayout.rectOf(modelData, root.width, root.height, slot.piece?.size)
            readonly property var nat: LockLayout.natural(modelData, slot.piece?.size)
            width: nat.w; height: nat.h
            x: r.x + r.w / 2 - width / 2
            y: r.y + r.h / 2 - height / 2
            scale: r.k
            rotation: modelData.rot
            opacity: modelData.opacity
            focus: modelData.type === "field"
            Loader {
                anchors.fill: parent
                focus: true
                sourceComponent: ({ clock: clockC, avatar: avatarC, name: nameC, field: fieldC, keyboard: keyboardC,
                                    battery: batteryC, notifications: notificationsC, piece: pieceC })[slot.modelData.type] ?? null
                onLoaded: {
                    if (item.hasOwnProperty("slot")) item.slot = slot
                    if (slot.modelData.type === "field") root.fieldInput = item.input
                }
            }
        }
    }

    // Text that stays sharp when its element is scaled.
    component LockText: StyledText { renderType: Text.QtRendering }

    Component {
        id: clockC
        ColumnLayout {
            spacing: 2
            LockText {
                Layout.alignment: Qt.AlignHCenter
                text: DateTime.time
                font.pixelSize: 84; font.weight: Font.Bold
                font.family: Appearance.font.family.numbers
                color: "white"
            }
            LockText {
                Layout.alignment: Qt.AlignHCenter
                text: DateTime.collapsedCalendarFormat
                font.pixelSize: Appearance.font.pixelSize.larger
                color: "white"; opacity: 0.7
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                visible: (Config.options?.clock?.showOnLock ?? true) && Chrono.nextAlarmText !== ""
                MaterialSymbol { text: "alarm"; iconSize: 16; color: "white"; opacity: 0.6 }
                LockText { text: Chrono.nextAlarmText; font.pixelSize: Appearance.font.pixelSize.small; color: "white"; opacity: 0.6 }
            }
        }
    }
    Component {
        id: avatarC
        Item {
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Appearance.colors.colLayer1
                border.width: 3; border.color: Appearance.colors.colPrimary
            }
            Image {
                id: av
                anchors.fill: parent; anchors.margins: 5
                source: root.ctx?.avatar ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask { maskSource: Rectangle { width: av.width; height: av.height; radius: av.width / 2 } }
            }
            MaterialSymbol {
                anchors.centerIn: parent; text: "person"; iconSize: 48
                color: Appearance.colors.colPrimary
                visible: av.status !== Image.Ready
            }
        }
    }
    Component {
        id: nameC
        LockText {
            text: root.ctx?.user ?? ""
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.huge; font.weight: Font.DemiBold
            font.capitalization: Font.Capitalize
            elide: Text.ElideRight
            color: "white"
        }
    }
    Component {
        id: fieldC
        LockField {
            ctx: root.ctx
            miniature: root.miniature
            focus: true
        }
    }
    Component {
        id: keyboardC
        Rectangle {
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.12)
            RowLayout {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol { text: "keyboard"; iconSize: 18; color: "white"; opacity: 0.8 }
                LockText {
                    text: (KeyboardLayoutService.currentLayoutCode || KeyboardLayoutService.currentLayoutName || "—").toUpperCase()
                    color: "white"; font.weight: Font.DemiBold
                }
            }
        }
    }
    Component {
        id: batteryC
        Rectangle {
            readonly property int pct: Math.round((Battery.percentage ?? 0) * 100)
            visible: Battery.available || root.showEmpty
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.12)
            RowLayout {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: Battery.isCharging ? "battery_charging_full" : !Battery.available ? "battery_unknown"
                        : parent.parent.pct >= 90 ? "battery_full" : parent.parent.pct >= 50 ? "battery_5_bar"
                        : parent.parent.pct >= 20 ? "battery_3_bar" : "battery_alert"
                    iconSize: 18; color: Battery.isLow ? Appearance.colors.colError : "white"
                }
                LockText { text: Battery.available ? `${parent.parent.pct}%` : "Battery"; color: "white"; font.weight: Font.DemiBold }
            }
        }
    }
    Component {
        id: notificationsC
        Item {
            LockNotifications { anchors { left: parent.left; right: parent.right; top: parent.top } }
            Rectangle {
                anchors.fill: parent
                visible: root.showEmpty
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2)
                LockText {
                    anchors.centerIn: parent
                    text: (Config.options?.lock?.notifications?.enable ?? false) ? "Notifications that arrive while locked" : "Notifications (off in Settings)"
                    color: "white"; opacity: 0.7
                }
            }
        }
    }
    Component {
        id: pieceC
        Item {
            id: pc
            property Item slot: null
            readonly property var entry: pc.slot?.piece ?? null
            // Shown, never touched: a piece on the lock takes no input.
            enabled: false
            SurfaceMaterial {
                anchors.fill: parent
                visible: !pc.entry || pc.entry.frame !== false
                surface: "piece"
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                textColor: Appearance.colors.colOnLayer1
            }
            Loader {
                anchors.fill: parent
                anchors.margins: pc.entry?.frame === false ? 0 : 12
                asynchronous: true
                active: !!pc.entry && Pieces.usable(pc.entry.id)
                source: active ? pc.entry.url : ""
                onLoaded: {
                    if (item.hasOwnProperty("ctx")) item.ctx = { live: true, screenName: root.ctx?.screen?.name ?? "", cell: pc.entry.size }
                    if (item.hasOwnProperty("settings")) {
                        const s = {}
                        for (const d of pc.entry.settings ?? []) if (d.key) s[d.key] = d.default
                        item.settings = Object.assign(s, pc.slot?.modelData?.settings?.values ?? {})
                    }
                }
            }
            LockText {
                anchors.centerIn: parent
                visible: !pc.entry
                text: `"${pc.slot?.modelData?.settings?.id ?? "?"}" isn't installed`
                color: "white"; opacity: 0.7
            }
        }
    }
}
