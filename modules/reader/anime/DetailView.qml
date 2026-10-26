import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.reader.components

Item {
    id: detailView

    readonly property string fontDisplay: Appearance.font.family.title
    readonly property string fontBody:    Appearance.font.family.main

    signal backRequested()

    readonly property bool _inLibrary:
        ReaderAnime.currentAnime ? ReaderAnime.isInLibrary(ReaderAnime.currentAnime.id) : false

    // ── Playback ──────────────────────────────────────────────────────────────
    // mpv belongs to anod's reader (Reader.play), not this view, so it keeps
    // playing when the panel closes or this view goes away.
    function _playWithMpv(url, referer, subtitle, title) {
        if (!url || url.length === 0) {
            console.warn("[AnimeDetail] _playWithMpv called with empty URL, aborting")
            return
        }
        Reader.play({ url: url, referer: referer, subtitle: subtitle }, title || "Anime",
            ReaderAnime.currentAnime?.id ?? "", ReaderAnime.currentEpisode)
        ReaderAnime.playedShow = ReaderAnime.currentAnime?.id ?? ""
    }
    // (no backdrop of its own: the panel's SurfaceMaterial shows through)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: Appearance.m3colors.m3surfaceContainerLow
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 6; rightMargin: 10 }
                spacing: 2

                // Back
                Item {
                    width: 44; height: 44

                    Rectangle {
                        anchors.centerIn: parent; width: 34; height: 34; radius: 17
                        color: backArea.containsMouse ? Appearance.m3colors.m3surfaceContainer : "transparent"
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(130) } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "←"; font.pixelSize: 18; color: Appearance.m3colors.m3onSurfaceVariant
                    }
                    MouseArea {
                        id: backArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: detailView.backRequested()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: ReaderAnime.currentAnime
                        ? (ReaderAnime.currentAnime.englishName || ReaderAnime.currentAnime.name || "")
                        : ""
                    font.family: detailView.fontDisplay
                    font.pixelSize: 14; color: Appearance.m3colors.m3onSurface; elide: Text.ElideRight
                }

                Item {
                    visible: ReaderAnime.currentAnime !== null
                    width: libBtnLabel.implicitWidth + 28; height: 32

                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: detailView._inLibrary ? Appearance.m3colors.m3primaryContainer : Appearance.m3colors.m3surfaceContainer
                        border.color: detailView._inLibrary ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outlineVariant
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                    }
                    Row {
                        anchors.centerIn: parent; spacing: 5

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: detailView._inLibrary ? "✓" : "+"
                            font.pixelSize: 11; font.bold: true
                            color: detailView._inLibrary
                                ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                        }
                        StyledText {
                            id: libBtnLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Library"
                            font.family: detailView.fontBody
                            font.pixelSize: 11; font.letterSpacing: 0.3
                            color: detailView._inLibrary
                                ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3onSurfaceVariant
                            Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(180) } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            if (detailView._inLibrary)
                                ReaderAnime.removeFromLibrary(ReaderAnime.currentAnime.id)
                            else
                                ReaderAnime.addToLibrary(ReaderAnime.currentAnime)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 34
            color: Appearance.m3colors.m3surfaceContainer
            visible: ReaderAnime.currentAnime !== null

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }

                StyledText {
                    text: ReaderAnime.currentAnime
                        ? (ReaderAnime.currentAnime.episodes
                        ? ReaderAnime.currentAnime.episodes.length : 0) + " episodes"
                        : ""
                    font.family: detailView.fontBody
                    font.pixelSize: 11; font.letterSpacing: 1
                    color: Appearance.m3colors.m3onSurfaceVariant; opacity: 0.75
                }

                Item { Layout.fillWidth: true }

                // Last-watched badge
                Rectangle {
                    readonly property var _entry: ReaderAnime.currentAnime
                        ? ReaderAnime.getLibraryEntry(ReaderAnime.currentAnime.id) : null
                    visible: _entry !== null && _entry !== undefined
                        && _entry.lastWatchedEpNum !== ""
                        && _entry.lastWatchedEpNum !== undefined
                    height: 20; width: lastWatchedText.implicitWidth + 18; radius: 10
                    color: ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.12)
                    border.color: Appearance.m3colors.m3primary; border.width: 1

                    Text {
                        id: lastWatchedText; anchors.centerIn: parent
                        text: {
                            var e = ReaderAnime.currentAnime
                                ? ReaderAnime.getLibraryEntry(ReaderAnime.currentAnime.id) : null
                            return e ? "Last: Ep. " + e.lastWatchedEpNum : ""
                        }
                        font.family: detailView.fontBody
                        font.pixelSize: 9; font.letterSpacing: 0.8; color: Appearance.m3colors.m3primary
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.3
            }
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            SkeletonList {
                anchors.fill: parent; z: 5
                active: ReaderAnime.isFetchingDetail
                rowHeight: 52
                subtitle: false
                dividerInset: 64
            }

            LoadingState {
                anchors.fill: parent; z: 6
                active: ReaderAnime.isFetchingLinks
                color: ColorUtils.transparentize(Appearance.m3colors.m3background, 0.88)
                label: "fetching stream"
                detail: ReaderAnime.currentEpisode ? "Episode " + ReaderAnime.currentEpisode : ""
                bodyFont: detailView.fontBody
            }

            // Links error toast
            Rectangle {
                id: linksErrorToast
                anchors {
                    bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                    bottomMargin: 12
                }
                height: 36; radius: 18
                width: linksErrText.implicitWidth + 28
                color: Appearance.m3colors.m3errorContainer
                visible: ReaderAnime.linksError.length > 0 && !ReaderAnime.isFetchingLinks
                z: 7

                Text {
                    id: linksErrText; anchors.centerIn: parent
                    text: ReaderAnime.linksError
                    font.family: detailView.fontBody
                    font.pixelSize: 11; color: Appearance.m3colors.m3onErrorContainer; elide: Text.ElideRight
                }
            }

            ListView {
                ReaderWheel {}
                id: epList
                anchors.fill: parent; clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: ReaderAnime.currentAnime ? ReaderAnime.currentAnime.episodes : []

                ScrollBar.vertical: StyledScrollBar {
                }

                delegate: ClickableRect {
                    id: epRowAreaRect
                    width: epList.width; height: 52

                    readonly property var _libEntry: ReaderAnime.currentAnime
                        ? ReaderAnime.getLibraryEntry(ReaderAnime.currentAnime.id) : null
                    readonly property bool isLastWatched:
                        _libEntry !== null && _libEntry !== undefined
                        && _libEntry.lastWatchedEpNum === String(modelData.number)
                    // anod's saved position for this episode (resume, watched)
                    readonly property var _prog: ReaderAnime.progress[String(modelData.number)] ?? null

                    color: isLastWatched
                        ? ColorUtils.transparentize(Appearance.m3colors.m3primary, 0.07)
                        : (epRowAreaRect.pressed
                            ? Appearance.m3colors.m3surfaceContainerHigh
                            : (epRowAreaRect.hovered ? Appearance.m3colors.m3surfaceContainer : "transparent"))
                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(110) } }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left; right: parent.right
                            leftMargin: 64; rightMargin: 16
                        }
                        height: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.22
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 14

                        Rectangle {
                            width: epPillText.implicitWidth + 16; height: 26; radius: 13
                            color: isLastWatched ? Appearance.m3colors.m3primary : Appearance.m3colors.m3primaryContainer

                            StyledText {
                                id: epPillText; anchors.centerIn: parent
                                text: "Ep." + (modelData.number || "?")
                                font.family: detailView.fontBody
                                font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5
                                color: isLastWatched ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onPrimaryContainer
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Episode " + (modelData.number || "")
                            font.family: detailView.fontBody
                            font.pixelSize: 12; color: Appearance.m3colors.m3onSurface; elide: Text.ElideRight
                        }

                        // Watched, or how far it got (resumes there)
                        StyledText {
                            visible: !!epRowAreaRect._prog
                            text: !epRowAreaRect._prog ? "" : epRowAreaRect._prog.watched ? "✓ watched"
                                : epRowAreaRect._prog.dur > 0 ? `${Math.round(100 * epRowAreaRect._prog.pos / epRowAreaRect._prog.dur)}%`
                                : ""
                            font.pixelSize: 10
                            color: epRowAreaRect._prog?.watched ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outline
                        }

                        // Play icon
                        StyledText {
                            text: "▶"; font.pixelSize: 13
                            color: epRowAreaRect.hovered ? Appearance.m3colors.m3primary : Appearance.m3colors.m3outline
                            opacity: epRowAreaRect.hovered ? 0.9 : 0.35
                            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(120) } }
                            Behavior on color   { ColorAnimation  { duration: AnimationConfig.scaledDuration(120) } }
                        }
                    }

                    onClicked: {
                            if (!ReaderAnime.currentAnime) return

                            ReaderAnime.fetchStreamLinks(
                                ReaderAnime.currentAnime.id,
                                modelData.number,
                                "best"
                            )

                            if (ReaderAnime.isInLibrary(ReaderAnime.currentAnime.id)) {
                                ReaderAnime.updateLastWatched(
                                    ReaderAnime.currentAnime.id,
                                    modelData.id,
                                    modelData.number
                                )
                            }
                        }
                }
            }
        }
    }

    Connections {
        target: ReaderAnime
        function onSelectedLinkChanged() {
            if (!ReaderAnime.selectedLink) return
            var lnk = ReaderAnime.selectedLink
            if (lnk.error) {
                console.warn("[AnimeDetail] selectedLink has error:", lnk.error)
                ReaderAnime.clearStreamLinks()
                return
            }
            if (!lnk.url || lnk.url.length === 0) {
                console.warn("[AnimeDetail] selectedLink has no URL, aborting playback")
                ReaderAnime.clearStreamLinks()
                return
            }

            var title = ReaderAnime.currentAnime
                ? (ReaderAnime.currentAnime.englishName || ReaderAnime.currentAnime.name)
                + " — Ep." + ReaderAnime.currentEpisode
                : ""
            detailView._playWithMpv(lnk.url, lnk.referer, lnk.subtitle, title)
            ReaderAnime.clearStreamLinks()
        }
    }
}
