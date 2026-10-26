import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bundled widget: Google News RSS (no key; personal use under Google's
// terms). Fetched when placed and every 30 minutes after; nothing runs when
// the widget isn't on a page. The local feed sends the chosen place to Google.
// Idea from Ryoku's NewsService.
Item {
    id: root
    property var ctx
    property var settings: ({})

    readonly property var topics: ["WORLD", "NATION", "BUSINESS", "TECHNOLOGY", "ENTERTAINMENT", "SCIENCE", "SPORTS", "HEALTH"]
    readonly property string feed: root.settings?.feed ?? "top"
    readonly property string country: /^[A-Za-z]{2}$/.test(root.settings?.country ?? "") ? root.settings.country.toUpperCase() : "US"
    readonly property string language: /^[A-Za-z]{2,3}(-[A-Za-z]{2})?$/.test(root.settings?.language ?? "") ? root.settings.language : "en"
    readonly property string url: {
        const q = `hl=${root.language}-${root.country}&gl=${root.country}&ceid=${root.country}:${root.language}`
        const place = (root.settings?.place ?? "").trim()
        if (root.feed === "local" && place)
            return `https://news.google.com/rss/headlines/section/geo/${encodeURIComponent(place)}?${q}`
        if (root.feed === "topic" && root.topics.includes(root.settings?.topic))
            return `https://news.google.com/rss/headlines/section/topic/${root.settings.topic}?${q}`
        return `https://news.google.com/rss?${q}`
    }
    readonly property string title: root.feed === "local" && (root.settings?.place ?? "").trim() ? root.settings.place.trim()
        : root.feed === "topic" ? (root.settings?.topic ?? "News").charAt(0) + (root.settings?.topic ?? "news").slice(1).toLowerCase()
        : "Top stories"

    property var items: []      // [{ title, source, site, link, time }]
    // Google News' feed carries no article images: each row shows its
    // source's icon instead (Google's favicon service, given only the site).
    readonly property bool icons: root.settings?.icons ?? true
    property string error: ""

    function decode(s) {
        return String(s ?? "").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
            .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'")
            .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(parseInt(n, 10)))
            .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16))).replace(/&amp;/g, "&").trim()
    }
    function parse(xml) {
        const out = []
        const re = /<item>([\s\S]*?)<\/item>/g
        let m
        while ((m = re.exec(xml)) && out.length < 20) {
            const get = tag => (m[1].match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`)) ?? [])[1] ?? ""
            const source = root.decode(get("source"))
            let t = root.decode(get("title"))
            // Google appends " - Source" to each headline.
            if (source && t.endsWith(" - " + source)) t = t.slice(0, -(source.length + 3))
            const link = root.decode(get("link"))
            const site = (m[1].match(/<source[^>]*url="https?:\/\/([^"\/]+)/) ?? [])[1] ?? ""
            if (t && /^https:\/\//.test(link))
                out.push({ title: t, source: source, site: /^[A-Za-z0-9.-]+$/.test(site) ? site : "", link: link, time: Date.parse(root.decode(get("pubDate"))) || 0 })
        }
        return out
    }
    function ago(t) {
        const mins = Math.round((Date.now() - t) / 60000)
        return !t ? "" : mins < 60 ? `${Math.max(1, mins)} min` : mins < 1440 ? `${Math.round(mins / 60)} h` : `${Math.round(mins / 1440)} d`
    }
    // A change while a fetch runs (the settings arrive after the first one
    // starts) fetches again when it ends, so the old feed never sticks.
    property bool _again: false
    function refresh() { if (fetcher.running) root._again = true; else fetcher.running = true }
    // The settings land just after creation: start a moment later so the
    // first fetch is already the right feed.
    property bool _started: false
    onUrlChanged: if (root._started) refresh()
    Timer { running: true; interval: 250; onTriggered: { root._started = true; root.refresh() } }

    Process {
        id: fetcher
        command: ["curl", "-sfL", "--max-time", "15", "-A", "Mozilla/5.0 (AnoShell news widget)", root.url]
        onRunningChanged: if (!running && root._again) { root._again = false; running = true }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._again) return    // an older feed's answer
                const list = root.parse(this.text || "")
                if (list.length) { root.items = list; root.error = "" }
                else root.error = (this.text || "").length ? "No headlines in the feed" : "Couldn't reach Google News"
            }
        }
    }
    Timer { interval: 30 * 60 * 1000; running: true; repeat: true; onTriggered: root.refresh() }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol { text: "newspaper"; iconSize: 18; color: Appearance.colors.colPrimary }
            StyledText { Layout.fillWidth: true; text: root.title; font.weight: Font.DemiBold; elide: Text.ElideRight }
            StyledText {
                visible: root.error.length > 0
                text: root.error; color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            spacing: 0
            model: root.items
            delegate: MouseArea {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width
                height: rowLayout.implicitHeight + 16
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: DefaultApps.launch(["xdg-open", row.modelData.link])
                Rectangle {     // separator above every row but the first
                    visible: row.index > 0
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.6
                }
                RowLayout {
                    id: rowLayout
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Rectangle {
                        visible: root.icons && row.modelData.site
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignTop
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2
                        Image {
                            anchors.centerIn: parent
                            width: 20; height: 20
                            sourceSize: Qt.size(40, 40)
                            asynchronous: true
                            source: parent.visible ? `https://www.google.com/s2/favicons?domain=${row.modelData.site}&sz=64` : ""
                        }
                    }
                ColumnLayout {
                    id: col
                    Layout.fillWidth: true
                    spacing: 3
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.title
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        color: row.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: [row.modelData.source, root.ago(row.modelData.time)].filter(s => s).join(" · ")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideRight
                    }
                }
                }
            }
        }
    }
}
