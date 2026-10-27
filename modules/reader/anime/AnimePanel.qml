import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.reader.components
import qs.modules.common.widgets as W

Item {
    id: root
    implicitWidth: 540

    readonly property string fontBody: Appearance.font.family.main

    // ── Tab state ─────────────────────────────────────────────────────────────
    property int tabIndex: 0       // 0 = Browse, 1 = Library, 2 = Airing (reader.anime.airing)
    Connections {
        target: ReaderAnime
        function onAiringEnabledChanged() { if (!ReaderAnime.airingEnabled && root.tabIndex === 2) root.tabIndex = 0 }
    }

    // ── Navigation stacks (0 = list, 1 = detail) ──────────────────────────────
    // No "reader" stack — MPV handles playback externally
    property int browseStack:  0
    property int libraryStack: 0

    // The host (ReaderHost) hides the panel but keeps it loaded, so the
    // toggle brings it back exactly as it was left.
    signal minimizeRequested()
    function minimize() { root.minimizeRequested() }

    // ── Background ────────────────────────────────────────────────────────────
    W.SurfaceMaterial {
        anchors.fill: parent
        surface: "reader"
        // Connected frame: it paints the panel (fused, curved, blurred) itself.
        color: PanelRegistry.enabled ? "transparent" : Appearance.colors.colLayer0
        radius: PanelRegistry.enabled ? 0 : Appearance.rounding.normal
        // Top edge shadow / divider
        Divider {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            opacity: 0.5
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Main content (Browse / Library stacks) ────────────────────────────
        Item { // the tabs: both keep full size (a 0×0 hidden tab made its lists build every row)
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── Browse tab ────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: root.tabIndex === 0
                BrowseView {
                    id: browseView
                    anchors.fill: parent
                    visible: root.browseStack === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                    onAnimeSelected: function(show) {
                        ReaderAnime.fetchAnimeDetail(show)
                        root.browseStack = 1
                    }
                }

                DetailView {
                    anchors.fill: parent
                    visible: root.browseStack === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                    onBackRequested: {
                        root.browseStack = 0
                        ReaderAnime.clearDetail()
                    }
                }
            }

            // ── Airing tab ────────────────────────────────────────────────────
            AiringView {
                anchors.fill: parent
                visible: root.tabIndex === 2 && ReaderAnime.airingEnabled
                onSearchRequested: title => {
                    root.tabIndex = 0
                    root.browseStack = 0
                    browseView.searchFor(title)
                }
            }

            // ── Library tab ───────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: root.tabIndex === 1
                LibraryView {
                    anchors.fill: parent
                    visible: root.libraryStack === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                    onAnimeSelected: function(show) {
                        ReaderAnime.fetchAnimeDetail(show)
                        root.libraryStack = 1
                    }
                }

                DetailView {
                    anchors.fill: parent
                    visible: root.libraryStack === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                    onBackRequested: {
                        root.libraryStack = 0
                        ReaderAnime.clearDetail()
                    }
                }
            }
        }

        // ── Bottom tab bar ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: Appearance.colors.colLayer1

            // Top hairline
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.4
            }

            IconButton {
                id: minimizeButton
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                icon: "minimize"
                onClicked: root.minimize()
            }

            Row {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: minimizeButton.left; rightMargin: 8 }

                Repeater {
                    model: [
                        { label: "Browse",  icon: "⊞" },
                        { label: "Library", icon: "⊟" }
                    ].concat(ReaderAnime.airingEnabled ? [{ label: "Airing", icon: "◷" }] : [])

                    delegate: Item {
                        width: (root.width - 46) / (ReaderAnime.airingEnabled ? 3 : 2)
                        height: parent.height

                        readonly property bool active: root.tabIndex === index

                        Rectangle {
                            anchors.fill: parent
                            color: tabArea.containsMouse && !active
                                ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.05)
                                : "transparent"
                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.pixelSize: 13
                                color: active ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurfaceVariant
                                opacity: active ? 1 : 0.5
                                Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.family: root.fontBody
                                font.pixelSize: 10
                                font.letterSpacing: 0.6
                                color: active ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurfaceVariant
                                opacity: active ? 1 : 0.5
                                Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                            }
                        }

                        // Active indicator — top edge (drawer is at bottom, indicator on top)
                        Rectangle {
                            anchors {
                                top: parent.top
                                horizontalCenter: parent.horizontalCenter
                            }
                            width: active ? 28 : 0
                            height: 2; radius: 1
                            color: Appearance.m3colors.m3primary
                            Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.tabIndex = index
                        }
                    }
                }
            }
        }
    }

    PanelDecor {
        title: "anime"
    }
}
