import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * General settings — elaborate with collapsible cards, detailed controls,
 * visual indicators, and comprehensive audio/battery/time/notification config.
 */
ColumnLayout {
    spacing: 16

    // configRoots match this page's setNestedValue writes — `sounds.battery`
    // dotted because ModulesConfig owns `sounds.theme`.
    SettingsPageHeader {
        title: "General"
        subtitle: "Audio, battery, time, notifications, scrolling, sounds"
        configRoots: ["audio", "battery", "time", "notifications", "interactions", "sounds.battery", "sounds.volume",
            "sounds.login", "sounds.notifications", "sounds.panels", "sounds.alerts", "sounds.alertThreshold", "sounds.alertGap",
            "session", "polkit", "lock"]
    }

    // ═══ Audio ═══
    SettingsCard {
        icon: "volume_up"
        title: "Audio"
        subtitle: "Volume protection, system sounds, and audio behavior"
        configKeys: ["audio"]

        // Current volume indicator
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            CircularProgress {
                implicitSize: 48; lineWidth: 3
                value: Audio.sink?.audio?.volume ?? 0
                colPrimary: (Audio.sink?.audio?.volume ?? 0) > 1 ? Appearance?.m3colors.m3error ?? "#BA1A1A" : Appearance?.colors.colPrimary ?? "#65558F"
            }
            ColumnLayout {
                spacing: 2
                StyledText {
                    text: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}%`
                    font.pixelSize: Appearance?.font.pixelSize.large ?? 18
                    font.weight: Font.Bold
                    font.family: Appearance?.font.family.numbers ?? "monospace"
                }
                StyledText {
                    text: Audio.sink?.audio?.muted ? "Muted" : (Audio.friendlyDeviceName(Audio.sink) ?? "Default sink")
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    opacity: 0.5
                    elide: Text.ElideRight
                    Layout.maximumWidth: 200
                }
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSwitch {
            label: "EasyEffects quick toggle"
            configKey: "audio.easyEffects.enable"
            sublabel: EasyEffects.enabled && !EasyEffects.available
                ? "EasyEffects isn't running: start it (e.g. its service mode) and the toggle appears"
                : "Bypass and output presets in the quick toggles, through EasyEffects' own command line. Needs `easyeffects`"
            checked: Config.options?.audio?.easyEffects?.enable ?? false
            onCheckedChanged: Config.setNestedValue("audio.easyEffects.enable", checked)
        }

        ConfigSwitch {
            label: "Volume protection (Earbang guard)"
            configKey: "audio.protection.enable"
            sublabel: "Blocks sudden volume jumps that could damage hearing"
            checked: Config.options?.audio?.protection?.enable ?? false
            onCheckedChanged: Config.setNestedValue("audio.protection.enable", checked)
        }

        ConfigSlider {
            label: "Max allowed increase per step"
            configKey: "audio.protection.maxAllowedIncrease"
            sublabel: "Maximum % the volume can jump in a single change"
            from: 1; to: 50; stepSize: 1
            value: Config.options?.audio?.protection?.maxAllowedIncrease ?? 10
            onValueChanged: Config.setNestedValue("audio.protection.maxAllowedIncrease", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Hard volume limit"
            configKey: "audio.protection.maxAllowed"
            sublabel: "Absolute maximum volume percentage (pavucontrol allows up to 153%)"
            from: 50; to: 200; stepSize: 5
            value: Config.options?.audio?.protection?.maxAllowed ?? 100
            onValueChanged: Config.setNestedValue("audio.protection.maxAllowed", Math.round(value))
            valueText: `${Math.round(value)}%`
        }
    }

    // ═══ Sound effects ═══
    SettingsCard {
        icon: "music_note"
        title: "Sound effects"
        subtitle: "Short sounds for logging in, notifications, panels and alerts, played with pw-play. All off until you turn them on. Needs `pipewire` (pw-play)."
        configKeys: ["sounds.volume", "sounds.login", "sounds.notifications", "sounds.panels", "sounds.alerts", "sounds.alertThreshold", "sounds.alertGap"]

        ConfigSlider {
            label: "Volume"
            configKey: "sounds.volume"
            sublabel: "For every sound effect and the battery sounds, under the system volume"
            from: 0; to: 100; stepSize: 5
            value: Math.round((Config.options?.sounds?.volume ?? 0.6) * 100)
            onValueChanged: Config.setNestedValue("sounds.volume", Math.round(value) / 100)
            valueText: `${Math.round(value)}%`
        }
        ConfigRow {
            label: "Try it"
            sublabel: "Plays the notification sound at this volume"
            RippleButton {
                buttonText: "Play"
                onClicked: Sounds.play("notification")
            }
        }
        ConfigSwitch {
            label: "When the desktop first appears"
            configKey: "sounds.login"
            sublabel: "Once per session, not when the shell restarts"
            checked: Config.options?.sounds?.login ?? false
            onCheckedChanged: Config.setNestedValue("sounds.login", checked)
        }
        ConfigSwitch {
            label: "Notifications"
            configKey: "sounds.notifications"
            sublabel: "An app's own sound (sound-name, sound-file) plays instead; apps that ask for silence get none. Nothing plays while popups are held."
            checked: Config.options?.sounds?.notifications ?? false
            onCheckedChanged: Config.setNestedValue("sounds.notifications", checked)
        }
        ConfigSwitch {
            label: "Panels opening and closing"
            configKey: "sounds.panels"
            sublabel: "Sidebars, launcher, overview, control panel and the other panels"
            checked: Config.options?.sounds?.panels ?? false
            onCheckedChanged: Config.setNestedValue("sounds.panels", checked)
        }
        ConfigSwitch {
            label: "Alerts"
            configKey: "sounds.alerts"
            sublabel: "CPU or memory use going over the limit below, or the battery reaching its critical level while unplugged"
            checked: Config.options?.sounds?.alerts ?? false
            onCheckedChanged: Config.setNestedValue("sounds.alerts", checked)
        }
        ConfigSlider {
            label: "Alert above"
            configKey: "sounds.alertThreshold"
            enabled: Config.options?.sounds?.alerts ?? false
            from: 50; to: 100; stepSize: 5
            value: Config.options?.sounds?.alertThreshold ?? 90
            onValueChanged: Config.setNestedValue("sounds.alertThreshold", Math.round(value))
            valueText: `${Math.round(value)}%`
        }
        ConfigSlider {
            label: "Quiet time between alerts"
            configKey: "sounds.alertGap"
            sublabel: "How long a value must stay under the limit before it can sound again"
            enabled: Config.options?.sounds?.alerts ?? false
            from: 0; to: 1800; stepSize: 30
            value: Config.options?.sounds?.alertGap ?? 300
            onValueChanged: Config.setNestedValue("sounds.alertGap", Math.round(value))
            valueText: Math.round(value) >= 60 ? `${(Math.round(value) / 60).toFixed(Math.round(value) % 60 ? 1 : 0)} min` : `${Math.round(value)} s`
        }
    }

    // ═══ Battery ═══
    SettingsCard {
        icon: "battery_full"
        title: "Battery"
        subtitle: "Warning thresholds, auto-suspend, and power notifications"
        configKeys: ["battery", "sounds.battery"]
        visible: Battery.available

        // Live battery indicator
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            CircularProgress {
                implicitSize: 56; lineWidth: 4
                value: Battery.percentage
                colPrimary: Battery.isLow && !Battery.isCharging ? Appearance?.m3colors.m3error ?? "#BA1A1A"
                    : Battery.isCharging ? Appearance.colors.colSuccess : Appearance?.colors.colPrimary ?? "#65558F"
            }
            ColumnLayout {
                spacing: 2
                RowLayout {
                    spacing: 4
                    StyledText {
                        text: `${Math.round(Battery.percentage * 100)}%`
                        font.pixelSize: Appearance?.font.pixelSize.huger ?? 24
                        font.weight: Font.Bold
                        font.family: Appearance?.font.family.numbers ?? "monospace"
                    }
                    MaterialSymbol {
                        text: Battery.isCharging ? "bolt" : ""
                        iconSize: 20; fill: 1; visible: Battery.isCharging
                        color: Appearance.colors.colSuccess
                    }
                }
                StyledText {
                    text: Battery.isCharging ? "Charging" : "On battery"
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    opacity: 0.5
                }
            }
            Item { Layout.fillWidth: true }
            // Health indicator
            ColumnLayout {
                spacing: 2; visible: Battery.health > 0
                StyledText { text: "Health"; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                StyledText {
                    text: `${Math.round(Battery.health)}%`
                    font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
                    font.weight: Font.DemiBold
                    font.family: Appearance?.font.family.numbers ?? "monospace"
                    color: Battery.health > 80 ? Appearance.colors.colSuccess : Battery.health > 50 ? Appearance.colors.colWarning : Appearance?.m3colors.m3error ?? "#BA1A1A"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSlider {
            label: "Low battery warning"
            configKey: "battery.low"
            sublabel: "Show notification when battery drops below this level"
            from: 5; to: 50; stepSize: 5
            value: Config.options?.battery?.low ?? 20
            onValueChanged: Config.setNestedValue("battery.low", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Critical battery warning"
            configKey: "battery.critical"
            sublabel: "Urgent notification with sound"
            from: 3; to: 30; stepSize: 1
            value: Config.options?.battery?.critical ?? 10
            onValueChanged: Config.setNestedValue("battery.critical", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Auto-suspend threshold"
            configKey: "battery.suspend"
            sublabel: "System suspends automatically below this level"
            from: 1; to: 15; stepSize: 1
            value: Config.options?.battery?.suspend ?? 5
            onValueChanged: Config.setNestedValue("battery.suspend", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSwitch {
            label: "Enable automatic suspend"
            configKey: "battery.automaticSuspend"
            sublabel: "Suspend the system when battery reaches the threshold above"
            checked: Config.options?.battery?.automaticSuspend ?? false
            onCheckedChanged: Config.setNestedValue("battery.automaticSuspend", checked)
        }

        ConfigSlider {
            label: "Full battery notification"
            configKey: "battery.full"
            sublabel: "Notify to unplug when charged above this level"
            from: 80; to: 100; stepSize: 1
            value: Config.options?.battery?.full ?? 100
            onValueChanged: Config.setNestedValue("battery.full", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        // Threshold-ordering check — these only make sense when
        // suspend < critical < low. Surfaces a warning if the user has
        // set them out of order.
        NoticeBox {
            readonly property int _low: Config.options?.battery?.low ?? 20
            readonly property int _critical: Config.options?.battery?.critical ?? 10
            readonly property int _suspend: Config.options?.battery?.suspend ?? 5
            readonly property bool _ordered: _suspend <= _critical && _critical <= _low
            visible: !_ordered
            iconName: "warning"
            text: `Threshold ordering looks off: suspend (${_suspend}%) ≤ critical (${_critical}%) ≤ low (${_low}%) is recommended.`
        }

        ConfigSwitch {
            label: "Battery sounds"
            configKey: "sounds.battery"
            sublabel: "Play sounds for charging, low battery, and full events"
            checked: Config.options?.sounds?.battery ?? true
            onCheckedChanged: Config.setNestedValue("sounds.battery", checked)
        }
    }

    // ═══ Time & Clock ═══
    SettingsCard {
        icon: "schedule"
        title: "Time & Clock"
        subtitle: "Clock format, date format, and second precision"
        configKeys: ["time"]

        // Live clock preview
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 56
            radius: Appearance?.rounding.small ?? 8
            color: Appearance?.colors.colLayer2 ?? "#2B2930"

            RowLayout {
                anchors.centerIn: parent; spacing: 12
                StyledText {
                    text: DateTime.time
                    font.pixelSize: Appearance?.font.pixelSize.huger ?? 28
                    font.weight: Font.Bold
                    font.family: Appearance?.font.family.numbers ?? "monospace"
                }
                StyledText {
                    text: "•"; font.pixelSize: Appearance.font.pixelSize.huge; opacity: 0.3
                }
                StyledText {
                    text: DateTime.longDate
                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                    opacity: 0.6
                }
            }
        }

        // Live-preview row for each format input — small text on the
        // right shows what the format actually renders against `now`.
        component TimeFormatRow: ConfigRow {
            id: tfRow
            property string formatKey: ""
            property string defaultValue: ""
            property int inputWidth: 120
            // Re-render the preview every minute for time formats; the
            // calling code can override with a faster timer if needed.
            // For day/month formats one-second precision is overkill.
            readonly property string previewText: {
                const fmt = (Config.options?.time?.[tfRow.formatKey] ?? tfRow.defaultValue)
                return Qt.locale().toString(new Date(), fmt)
            }

            RowLayout {
                spacing: 8
                StyledTextInput {
                    text: Config.options?.time?.[tfRow.formatKey] ?? tfRow.defaultValue
                    onEditingFinished: Config.setNestedValue(`time.${tfRow.formatKey}`, text)
                    Layout.preferredWidth: tfRow.inputWidth
                    font.family: Appearance?.font.family.mono ?? "monospace"
                }
                StyledText {
                    text: "→ " + tfRow.previewText
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    opacity: 0.7
                    elide: Text.ElideRight
                    Layout.maximumWidth: 220
                }
            }
        }

        TimeFormatRow {
            label: "Time format"
            sublabel: "Qt format: hh:mm (24h), h:mm AP (12h), hh:mm:ss (with seconds)"
            formatKey: "format"
            defaultValue: "hh:mm"
        }

        TimeFormatRow {
            label: "Short date format"
            formatKey: "shortDateFormat"
            defaultValue: "dd/MM"
        }

        TimeFormatRow {
            label: "Long date format"
            formatKey: "dateFormat"
            inputWidth: 180
            defaultValue: "dddd, dd/MM"
        }

        ConfigSwitch {
            label: "Second precision"
            configKey: "time.secondPrecision"
            sublabel: "Update clock every second (slightly more CPU usage)"
            checked: Config.options?.time?.secondPrecision ?? false
            onCheckedChanged: Config.setNestedValue("time.secondPrecision", checked)
        }
    }

    // ═══ Notifications ═══
    SettingsCard {
        icon: "notifications"
        title: "Notifications"
        subtitle: "Popup behavior, timeout, and sounds"
        configKeys: ["notifications"]

        // Notifications and the OSD in miniature: drag them where you want them.
        NotificationPreview { Layout.fillWidth: true }
        StyledText {
            Layout.fillWidth: true
            text: "Drag the notifications to a corner or an edge, their side handle to change their width, or the volume bar up or down."
            wrapMode: Text.Wrap
            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
        }

        // Where popups appear: click a spot on the miniature screen.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            readonly property string current: Config.options?.notifications?.position ?? "topRight"
            id: notifPos
            StyledText {
                text: "Popup position"
                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 200; implicitHeight: 120
                radius: 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                border.width: 1
                border.color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"
                StyledText { anchors.centerIn: parent; text: "Screen"; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.3 }
                Repeater {
                    model: [
                        { pos: "topLeft", x: 8, y: 8 }, { pos: "topCenter", x: 76, y: 8 }, { pos: "topRight", x: 144, y: 8 },
                        { pos: "bottomLeft", x: 8, y: 96 }, { pos: "bottomCenter", x: 76, y: 96 }, { pos: "bottomRight", x: 144, y: 96 }
                    ]
                    Rectangle {
                        required property var modelData
                        readonly property bool on: notifPos.current === modelData.pos
                        x: modelData.x; y: modelData.y; width: 48; height: 16
                        radius: 5
                        color: on ? Appearance?.colors.colPrimary ?? "#65558F" : "transparent"
                        border.width: 1
                        border.color: on ? Appearance?.colors.colPrimary ?? "#65558F" : Appearance?.colors.colOutlineVariant ?? "#44444488"
                        opacity: on ? 1 : 0.4
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.setNestedValue("notifications.position", modelData.pos)
                        }
                    }
                }
            }
        }

        ConfigSlider {
            label: "Auto-dismiss timeout"
            configKey: "notifications.timeout"
            sublabel: "How long popup notifications stay visible"
            from: 1000; to: 30000; stepSize: 1000
            value: Config.options?.notifications?.timeout ?? 7000
            onValueChanged: Config.setNestedValue("notifications.timeout", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigSwitch {
            label: "Silent mode"
            configKey: "notifications.silent"
            sublabel: "No popups — notifications still go to the history"
            checked: Config.options?.notifications?.silent ?? false
            onCheckedChanged: Config.setNestedValue("notifications.silent", checked)
        }

        ConfigSlider {
            label: "Popups on screen"
            configKey: "notifications.maxVisible"
            sublabel: "Newest popups shown at once; older ones wait in the history"
            from: 1; to: 10; stepSize: 1
            value: Config.options?.notifications?.maxVisible ?? 5
            onValueChanged: Config.setNestedValue("notifications.maxVisible", Math.round(value))
            valueText: `${Math.round(value)}`
        }

        ConfigRow {
            label: "Silent apps"
            configKey: "notifications.silentApps"
            sublabel: "Comma-separated app names: kept in the history, no popup"
            StyledTextInput {
                text: Array.from(Config.options?.notifications?.silentApps ?? []).join(", ")
                Layout.fillWidth: true
                onEditingFinished: Config.setNestedValue("notifications.silentApps",
                    text.split(",").map(s => s.trim()).filter(s => s.length > 0))
            }
        }

        ConfigRow {
            label: "Blocked apps"
            configKey: "notifications.blockedApps"
            sublabel: "Comma-separated app names: their notifications are dropped"
            StyledTextInput {
                text: Array.from(Config.options?.notifications?.blockedApps ?? []).join(", ")
                Layout.fillWidth: true
                onEditingFinished: Config.setNestedValue("notifications.blockedApps",
                    text.split(",").map(s => s.trim()).filter(s => s.length > 0))
            }
        }

        // See where and how long a popup shows with these settings.
        RippleButton {
            buttonText: "Send a test notification"
            onClicked: Quickshell.execDetached(["notify-send", "-a", "AnoShell", "Test notification",
                "This is where notifications appear, and how long they stay."])
        }
    }

    // ═══ Session ═══
    SettingsCard {
        icon: "power_settings_new"
        title: "Session"
        subtitle: "Confirmation for logout and shutdown"
        configKeys: ["session"]

        ConfigSwitch {
            label: "Press twice to log out"
            configKey: "session.confirmLogout"
            sublabel: "Off: a single click logs out"
            checked: Config.options?.session?.confirmLogout ?? true
            onCheckedChanged: Config.setNestedValue("session.confirmLogout", checked)
        }

        ConfigSwitch {
            label: "Press twice to shut down"
            configKey: "session.confirmShutdown"
            sublabel: "Off: a single click powers off"
            checked: Config.options?.session?.confirmShutdown ?? true
            onCheckedChanged: Config.setNestedValue("session.confirmShutdown", checked)
        }
    }

    // ═══ Password prompt (polkit) ═══
    SettingsCard {
        icon: "admin_panel_settings"
        title: "Password prompt"
        subtitle: "AnoShell asks for your password when an app needs permission (polkit)"
        configKeys: ["polkit"]

        ConfigSwitch {
            label: "Use AnoShell's password prompt"
            configKey: "polkit.enable"
            sublabel: !PolkitAuth.wanted ? "Off: another agent (or none) answers polkit"
                : PolkitAuth.registered ? "Active: AnoShell answers polkit in this session"
                : PolkitAuth.otherAgent ? "Another agent already answers in this session, so AnoShell's stays quiet"
                : "Registering…"
            checked: Config.options?.polkit?.enable ?? true
            onCheckedChanged: Config.setNestedValue("polkit.enable", checked)
        }
        ConfigSwitch {
            enabled: PolkitAuth.wanted
            label: "Blur behind the prompt"
            configKey: "polkit.blur"
            sublabel: "Off (default): only dims the screen; the bundled compositor configs leave quickshell:polkitPlain unblurred"
            checked: Config.options?.polkit?.blur ?? false
            onCheckedChanged: Config.setNestedValue("polkit.blur", checked)
        }
        NoticeBox {
            visible: PolkitAuth.wanted && PolkitAuth.otherAgent
            Layout.fillWidth: true
            iconName: "info"
            text: "polkit takes one agent per session. To use AnoShell's, stop the other one (e.g. remove hyprpolkitagent from your compositor's autostart, or `systemctl --user stop hyprpolkitagent`), then press Retry."
        }
        RippleButton {
            visible: PolkitAuth.wanted && PolkitAuth.otherAgent
            buttonText: "Retry"
            onClicked: PolkitAuth.retry()
        }
    }

    // ═══ Lock screen ═══
    SettingsCard {
        icon: "lock"
        title: "Lock screen"
        subtitle: CompositorService.compositor === "niri"
            ? "AnoShell locks the session (Super+L, loginctl lock-session, the session menu)"
            : "On Hyprland, hyprlock locks the session; here you can pick and preview AnoShell's lock screens for niri"
        configKeys: ["lock"]

        ConfigSwitch {
            label: "Lock with AnoShell (niri)"
            configKey: "lock.enable"
            sublabel: "Off: another locker (swaylock, hyprlock…) handles it"
            checked: Config.options?.lock?.enable ?? true
            onCheckedChanged: Config.setNestedValue("lock.enable", checked)
        }
        ConfigRow {
            label: "Lock screen"
            configKey: "lock.screen"
            sublabel: LockScreens.selected !== "default" && !LockScreens.current
                ? `"${LockScreens.selected}" doesn't load (${LockScreens.registry.errorsOf(LockScreens.selected).join("; ")}): the built-in one is used`
                : "More in Settings → Atelier → Lock screens, or make your own (docs/lockscreens.md)"
            ChoiceRow {
                model: [{ value: "default", label: "AnoShell", icon: "lock" }].concat(LockScreens.list.map(e => ({ value: e.id, label: e.name, icon: "style" })))
                current: LockScreens.selected
                onChose: value => LockScreens.select(value)
            }
        }
        // The chosen lock screen in miniature; the built-in one is arranged
        // here by dragging its parts (lock.layout).
        LockPreview { Layout.fillWidth: true }
        StyledText {
            Layout.fillWidth: true
            text: LockScreens.selected === "default" || !LockScreens.current
                ? "Drag the clock, your name, the status row or the password field anywhere; click one and drag its round handle to resize it."
                : "A lock screen package keeps its own layout."
            wrapMode: Text.Wrap
            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
        }
        RowLayout {
            spacing: 8
            RippleButton {
                buttonText: "Preview full screen"
                onClicked: LockScreens.preview(LockScreens.selected)
            }
            RippleButton {
                buttonText: "Reset layout"
                visible: Object.keys(Config.options?.lock?.layout ?? {}).length > 0
                onClicked: Config.setNestedValue("lock.layout", ({}))
            }
        }
        ConfigSwitch {
            label: "Fingerprint unlock"
            configKey: "lock.fingerprint.enable"
            sublabel: "Touch the reader instead of typing, when fprintd has your print (fprintd-enroll). The password always works too; after 3 failed scans only the password does"
            checked: Config.options?.lock?.fingerprint?.enable ?? false
            onCheckedChanged: Config.setNestedValue("lock.fingerprint.enable", checked)
        }
        ConfigSwitch {
            label: "Notifications on the lock screen"
            configKey: "lock.notifications.enable"
            sublabel: "The built-in lock screen lists the ones that arrive while locked"
            checked: Config.options?.lock?.notifications?.enable ?? false
            onCheckedChanged: Config.setNestedValue("lock.notifications.enable", checked)
        }
        ConfigSwitch {
            label: "Status row"
            configKey: "lock.statusRow.enable"
            sublabel: "Battery and network above the password field"
            checked: Config.options?.lock?.statusRow?.enable ?? false
            onCheckedChanged: Config.setNestedValue("lock.statusRow.enable", checked)
        }
        ConfigSwitch {
            label: "On-screen keyboard"
            configKey: "lock.osk.enable"
            checked: Config.options?.lock?.osk?.enable ?? false
            onCheckedChanged: Config.setNestedValue("lock.osk.enable", checked)
        }
        ConfigSwitch {
            label: "Dim when idle"
            configKey: "lock.dim.enable"
            sublabel: "Darkens the lock screen after 30 s without input"
            checked: Config.options?.lock?.dim?.enable ?? true
            onCheckedChanged: Config.setNestedValue("lock.dim.enable", checked)
        }
    }

    // ═══ Interactions ═══
    SettingsCard {
        icon: "touch_app"
        title: "Scrolling & Interactions"
        configKeys: ["interactions"]
        subtitle: "Touchpad and mouse scroll speed"

        ConfigSwitch {
            label: "Faster touchpad scrolling"
            configKey: "interactions.scrolling.fasterTouchpadScroll"
            sublabel: "Enhanced scroll speed for high-res touchpads"
            checked: Config.options?.interactions?.scrolling?.fasterTouchpadScroll ?? false
            onCheckedChanged: Config.setNestedValue("interactions.scrolling.fasterTouchpadScroll", checked)
        }

        ConfigSlider {
            label: "Touchpad scroll factor"
            configKey: "interactions.scrolling.touchpadScrollFactor"
            from: 10; to: 300; stepSize: 10
            value: Config.options?.interactions?.scrolling?.touchpadScrollFactor ?? 100
            onValueChanged: Config.setNestedValue("interactions.scrolling.touchpadScrollFactor", Math.round(value))
            valueText: `${Math.round(value)}`
        }

        ConfigSlider {
            label: "Mouse scroll factor"
            configKey: "interactions.scrolling.mouseScrollFactor"
            from: 10; to: 200; stepSize: 10
            value: Config.options?.interactions?.scrolling?.mouseScrollFactor ?? 50
            onValueChanged: Config.setNestedValue("interactions.scrolling.mouseScrollFactor", Math.round(value))
            valueText: `${Math.round(value)}`
        }
    }
}
