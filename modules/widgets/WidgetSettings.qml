import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * A placed widget's settings in edit mode, from its manifest's `settings`
 * list (bool, int, real, string, choice). Each change is saved at once.
 */
SurfaceMaterial {
    id: panel
    property var host // WidgetHost
    readonly property var defs: panel.host?.entry?.settings ?? []
    signal closed()
    surface: "widget"
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1
    textColor: Appearance.colors.colOnLayer1
    width: 320
    height: col.implicitHeight + 24

    function set(key, value) { Widgets.setSetting(panel.host.grid.screenName, panel.host.placed.uid, key, value) }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            StyledText { text: panel.host?.entry?.name ?? ""; font.weight: Font.DemiBold; Layout.fillWidth: true }
            RippleButton {
                implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
                onClicked: panel.closed()
                contentItem: MaterialSymbol { text: "close"; iconSize: 16; horizontalAlignment: Text.AlignHCenter }
            }
        }
        Repeater {
            model: panel.defs
            ColumnLayout {
                id: field
                required property var modelData
                readonly property var value: panel.host?.settings?.[modelData.key]
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { text: field.modelData.label ?? field.modelData.key; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    StyledSwitch {
                        visible: field.modelData.type === "bool"
                        checked: !!field.value
                        onToggled: panel.set(field.modelData.key, checked)
                    }
                }
                ConfigTextInput {
                    visible: ["string", "int", "real"].includes(field.modelData.type)
                    Layout.fillWidth: true
                    text: field.value === undefined || field.value === null ? "" : String(field.value)
                    validator: t => field.modelData.type === "string" || t === "" || isFinite(Number(t)) ? "" : "A number"
                    onEditingFinished: if (valid) panel.set(field.modelData.key,
                        field.modelData.type === "string" ? text : field.modelData.type === "int" ? Math.round(Number(text)) : Number(text))
                }
                ChoiceRow {
                    visible: field.modelData.type === "choice"
                    model: (field.modelData.options ?? []).map(o => ({ value: o, label: o }))
                    current: field.value
                    onChose: value => panel.set(field.modelData.key, value)
                }
            }
        }
    }
}
