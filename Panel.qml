import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "dechnik.zabbix"
    ipcTarget: "dechnik.zabbix"
    manageIpc: false

    property double nowMs: Date.now()
    property int cursorIndex: 0
    property bool cursorActive: false

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color barTextColor: bar ? bar.barForeground : Color.foreground
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property color dim: Qt.darker(foreground, 1.5)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property bool vertical: bar ? bar.vertical : false

    readonly property var selectedSeverities: Model.parseSeveritySelection(zabbix.selectedSeverities)
    readonly property var visibleProblems: Model.sortProblems(Model.filterProblems(zabbix.problems, selectedSeverities))
    readonly property var summary: Model.severitySummary(zabbix.problems, selectedSeverities, zabbix.hasData, zabbix.truncated)
    readonly property int summaryCount: summaryNumber()
    readonly property int summarySeverityValue: summaryValue()
    readonly property var summarySeverity: summarySeverityValue >= 0 ? Model.severityDefinition(summarySeverityValue) : null
    readonly property bool summaryAvailable: zabbix.hasData && (!summary || summary.available !== false)
    readonly property color summaryColor: summaryAvailable && summaryCount > 0 && summarySeverity ? summarySeverity.color : dim
    readonly property int cursorCount: Model.SEVERITIES.length + visibleProblems.length
    readonly property string activityGlyph: zabbix.loading ? "󰑐" : (zabbix.stale ? "󰅖" : "")
    readonly property string barCount: summaryAvailable ? String(summaryCount) : "?"

    function summaryNumber() {
        var value = summary && summary.count !== undefined ? Number(summary.count) : NaN;
        return isFinite(value) && value >= 0 ? Math.floor(value) : 0;
    }

    function summaryValue() {
        if (!summary)
            return -1;
        var value = summary.severityValue;
        if (value === undefined)
            value = summary.value;
        if (value === undefined)
            value = summary.severity;
        if (value && typeof value === "object")
            value = value.value;
        value = Number(value);
        return isFinite(value) && value >= 0 && value <= 5 ? Math.floor(value) : -1;
    }

    function severityLabel(definition) {
        if (!definition)
            return "Unknown";
        return String(definition.label !== undefined ? definition.label : definition.name || "Unknown");
    }

    function severitySelected(value) {
        return selectedSeverities.indexOf(Number(value)) !== -1;
    }

    function toggleSeverity(value) {
        value = Number(value);
        var next = selectedSeverities.slice();
        var index = next.indexOf(value);
        if (index >= 0) {
            if (next.length === 1)
                return;
            next.splice(index, 1);
        } else {
            next.push(value);
        }
        next.sort(function (a, b) {
            return a - b;
        });

        var entry = {
            id: moduleName
        };
        for (var key in settings)
            if (key !== "id")
                entry[key] = settings[key];
        entry.severities = next.map(function (value) {
            return String(value);
        });
        settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline(moduleName, entry);
    }

    function problemSeverity(problem) {
        var value = Number(problem ? problem.severity : -1);
        return isFinite(value) ? value : -1;
    }

    function hostsText(problem) {
        var hosts = problem && Array.isArray(problem.hosts) ? problem.hosts : [];
        var names = [];
        for (var i = 0; i < hosts.length; i++) {
            var host = hosts[i];
            var name = typeof host === "string" ? host : String(host && (host.name || host.host) || "");
            if (name !== "")
                names.push(name);
        }
        if (names.length > 0)
            return names.join(", ");
        return problem && problem.hostsAvailable === true ? "No visible hosts" : "Hosts unavailable";
    }

    function ageText(clock) {
        var value = Number(clock);
        return isFinite(value) && value > 0 ? Model.formatAge(value, nowMs) : "Start time unavailable";
    }

    function freshnessText() {
        if (zabbix.lastUpdatedMs <= 0)
            return "Never updated";
        var age = String(Model.formatAge(Math.floor(zabbix.lastUpdatedMs / 1000), nowMs) || "");
        if (age === "")
            return "Updated";
        return "Updated " + age;
    }

    function connectionLabel() {
        if (!zabbix.configured)
            return "Setup required";
        if (zabbix.loading && !zabbix.hasData) {
            var phase = String(zabbix.connectionState || "").toLowerCase();
            if (phase === "check_version" || phase === "checking-version")
                return "Checking server version";
            if (phase === "fetch_problems" || phase === "fetching-problems")
                return "Loading problems";
            if (phase === "enrich_hosts" || phase === "enriching-hosts")
                return "Loading host context";
            return "Connecting";
        }
        if (!zabbix.hasData && zabbix.lastError !== "")
            return "Connection error";
        if (zabbix.stale)
            return "Stale data";
        if (zabbix.hasData)
            return zabbix.insecureTls ? "Connected insecurely" : "Connected";
        return "Waiting for data";
    }

    function headerMeta() {
        var parts = [connectionLabel()];
        if (String(zabbix.serverVersion || "") !== "")
            parts.push("Zabbix " + zabbix.serverVersion);
        if (zabbix.lastUpdatedMs > 0)
            parts.push(freshnessText());
        return parts.join(" · ");
    }

    function errorTitle() {
        var labels = {
            endpoint: "Endpoint error",
            network: "Network error",
            dns: "Network error",
            timeout: "Request timed out",
            tls: "TLS verification failed",
            authentication: "Authentication failed",
            "token-file": "API token file error",
            permission: "API permission denied",
            http: "Zabbix HTTP error",
            transport: "Request transport failed",
            "json-rpc": "Zabbix API error",
            version: "Unsupported Zabbix version",
            malformed: "Invalid API response",
            "malformed-response": "Invalid API response"
        };
        return labels[String(zabbix.errorCategory || "")] || "Request failed";
    }

    function barTooltip() {
        if (!zabbix.configured)
            return "Zabbix · setup required";
        if (!summaryAvailable) {
            var unavailable = ["Zabbix", zabbix.loading ? "connecting" : "unavailable"];
            if (!zabbix.loading && zabbix.errorCategory !== "")
                unavailable.push(errorTitle());
            if (zabbix.insecureTls)
                unavailable.push("TLS verification disabled");
            return unavailable.join(" · ");
        }

        var parts = [];
        if (summaryCount === 0)
            parts.push("No matching Zabbix problems");
        else
            parts.push(summaryCount + " " + severityLabel(summarySeverity) + " problem" + (summaryCount === 1 ? "" : "s"));
        if (zabbix.loading)
            parts.push("refreshing");
        if (zabbix.stale)
            parts.push("stale");
        if (zabbix.truncated)
            parts.push("limited result");
        if (zabbix.insecureTls)
            parts.push("TLS verification disabled");
        return parts.join(" · ");
    }

    function safeErrorCategory() {
        var allowed = {
            endpoint: "endpoint",
            network: "network",
            dns: "network",
            timeout: "timeout",
            tls: "TLS",
            authentication: "authentication",
            "token-file": "token-file",
            permission: "permission",
            http: "HTTP",
            transport: "transport",
            "json-rpc": "API",
            version: "version",
            malformed: "response",
            "malformed-response": "response"
        };
        return allowed[String(zabbix.errorCategory || "")] || "request";
    }

    function safeVersion() {
        var match = String(zabbix.serverVersion || "").match(/^\d+(?:\.\d+){1,3}/);
        return match ? match[0] : "";
    }

    function safeSeverityName(value) {
        var names = ["not-classified", "information", "warning", "average", "high", "disaster"];
        return value >= 0 && value < names.length ? names[value] : "highest-selected";
    }

    function safeAge() {
        var elapsed = Math.max(0, Math.floor((Date.now() - Number(zabbix.lastUpdatedMs || 0)) / 1000));
        if (elapsed < 60)
            return elapsed + "s";
        if (elapsed < 3600)
            return Math.floor(elapsed / 60) + "m";
        if (elapsed < 86400)
            return Math.floor(elapsed / 3600) + "h";
        return Math.floor(elapsed / 86400) + "d";
    }

    function sanitizedStatus() {
        if (!zabbix.configured)
            return "zabbix setup-required";
        if (!zabbix.hasData) {
            if (zabbix.loading)
                return "zabbix connecting";
            return "zabbix unavailable category=" + safeErrorCategory();
        }

        var parts = ["zabbix"];
        if (summaryCount === 0)
            parts.push("problems=0");
        else {
            parts.push("severity=" + safeSeverityName(summarySeverityValue));
            parts.push("count=" + summaryCount);
        }
        if (zabbix.stale)
            parts.push("stale");
        if (zabbix.loading)
            parts.push("refreshing");
        if (zabbix.truncated)
            parts.push("truncated");
        if (zabbix.insecureTls)
            parts.push("insecure-tls");
        var version = safeVersion();
        if (version !== "")
            parts.push("version=" + version);
        if (zabbix.lastUpdatedMs > 0)
            parts.push("age=" + safeAge());
        return parts.join(" ");
    }

    function clampCursor() {
        cursorIndex = Math.max(0, Math.min(Math.max(0, cursorCount - 1), cursorIndex));
    }

    function moveCursor(dx, dy) {
        cursorActive = true;
        clampCursor();
        if (cursorCount === 0)
            return;
        var delta = dy !== 0 ? dy : dx;
        cursorIndex = Math.max(0, Math.min(cursorCount - 1, cursorIndex + delta));
        scrollCursorIntoView();
    }

    function activateCursor() {
        if (!cursorActive)
            return;
        if (cursorIndex >= 0 && cursorIndex < Model.SEVERITIES.length)
            toggleSeverity(Model.SEVERITIES[cursorIndex].value);
    }

    function setCursor(index) {
        cursorActive = true;
        cursorIndex = index;
    }

    function scrollItemIntoView(item) {
        if (!panelFlick || !item)
            return;
        Qt.callLater(function () {
            if (!item)
                return;
            var point = item.mapToItem(panelFlick.contentItem, 0, 0);
            var margin = Style.space(8);
            var top = point.y;
            var bottom = top + item.height;
            var maximum = Math.max(0, panelFlick.contentHeight - panelFlick.height);
            if (top < panelFlick.contentY + margin)
                panelFlick.contentY = Math.max(0, top - margin);
            else if (bottom > panelFlick.contentY + panelFlick.height - margin)
                panelFlick.contentY = Math.min(maximum, bottom + margin - panelFlick.height);
        });
    }

    function scrollCursorIntoView() {
        if (cursorIndex < Model.SEVERITIES.length)
            scrollItemIntoView(severityRepeater.itemAt(cursorIndex));
        else
            scrollItemIntoView(problemRepeater.itemAt(cursorIndex - Model.SEVERITIES.length));
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onOpenedChanged: if (opened) {
        cursorActive = false;
        cursorIndex = 0;
        nowMs = Date.now();
        if (panelFlick)
            panelFlick.contentY = 0;
        if (zabbix.configured && (!zabbix.hasData || zabbix.stale))
            zabbix.refresh();
    }
    onCursorCountChanged: clampCursor()

    Service {
        id: zabbix
        settings: root.settings
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.opened
        onTriggered: root.nowMs = Date.now()
    }

    IpcHandler {
        target: root.ipcTarget

        function open(): void {
            root.open();
        }
        function close(): void {
            root.close();
        }
        function show(): void {
            root.open();
        }
        function hide(): void {
            root.close();
        }
        function toggle(): void {
            root.toggle();
        }
        function refresh(): string {
            zabbix.refresh(true);
            return "ok";
        }
        function status(): string {
            return root.sanitizedStatus();
        }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: ""
        hasVisualContent: true
        labelVisible: false
        fixedWidth: root.vertical ? -1 : horizontalBarContent.implicitWidth + scaledHorizontalMargin * 2
        fixedHeight: root.vertical ? Style.bar.iconSlot * 2 : -1
        dimmed: !root.summaryAvailable || zabbix.loading || zabbix.stale
        tooltipText: root.barTooltip()

        onPressed: function (code) {
            if (code === Qt.RightButton)
                zabbix.refresh(true);
            else
                root.toggle();
        }

        Row {
            id: horizontalBarContent
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
                text: "󰀦"
                color: root.summaryColor
                font.family: root.fontFamily
                font.pixelSize: Style.bar.iconFont
                renderType: Text.NativeRendering
            }

            Text {
                text: root.barCount
                color: root.summaryAvailable ? root.barTextColor : Qt.darker(root.barTextColor, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                renderType: Text.NativeRendering
            }

            Text {
                visible: root.activityGlyph !== ""
                text: root.activityGlyph
                color: Qt.darker(root.barTextColor, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                renderType: Text.NativeRendering
            }
        }

        Column {
            visible: root.vertical
            anchors.fill: parent

            Text {
                width: parent.width
                height: Style.bar.iconSlot
                text: "󰀦"
                color: root.summaryColor
                font.family: root.fontFamily
                font.pixelSize: Style.bar.iconFont
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
            }

            Text {
                width: parent.width
                height: Style.bar.iconSlot
                text: root.barCount + (root.activityGlyph !== "" ? " " + root.activityGlyph : "")
                color: root.summaryAvailable ? root.barTextColor : Qt.darker(root.barTextColor, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
            }
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(430))
        contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent

            onMoveRequested: function (dx, dy) {
                root.moveCursor(dx, dy);
            }
            onActivateRequested: root.activateCursor()
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onTextKey: function (text) {
                if (String(text).toLowerCase() === "r")
                    zabbix.refresh(true);
            }

            Flickable {
                id: panelFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: contentColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Column {
                    id: contentColumn
                    width: panelFlick.width
                    spacing: Style.space(14)

                    Item {
                        id: heroBox
                        width: parent.width
                        implicitHeight: hero.implicitHeight
                        readonly property bool busy: zabbix.loading
                        function refresh() {
                            zabbix.refresh(true);
                        }

                        PanelHero {
                            id: hero
                            width: parent.width
                            title: "Zabbix problems"
                            meta: root.headerMeta()
                            detail: root.summaryAvailable ? String(root.visibleProblems.length) : ""
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            iconOpacity: zabbix.loading ? 0.55 : 1

                            iconComponent: Component {
                                Text {
                                    text: "󰀦"
                                    color: root.summaryColor
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.display
                                }
                            }

                            trailingControl: Component {
                                PanelActionButton {
                                    iconText: "󰑐"
                                    tooltipText: "Refresh Zabbix problems  (r)"
                                    foreground: hero.foreground
                                    fontFamily: hero.fontFamily
                                    enabled: !heroBox.busy
                                    onClicked: heroBox.refresh()
                                }
                            }
                        }
                    }

                    StateNotice {
                        message: "TLS certificate verification is disabled. The API token and monitoring data may be intercepted."
                        tone: root.urgent
                        visible: zabbix.insecureTls
                    }

                    StateNotice {
                        message: "Configure the Zabbix HTTPS URL and API token file in this widget's settings."
                        tone: root.dim
                        visible: !zabbix.configured
                    }

                    StateNotice {
                        message: zabbix.hasData ? "Refreshing problems; the last complete result remains visible." : "Connecting and loading Zabbix problems…"
                        tone: root.dim
                        visible: zabbix.configured && zabbix.loading
                    }

                    StateNotice {
                        message: "Showing the last complete result because the latest refresh failed."
                        tone: root.urgent
                        visible: zabbix.stale && zabbix.hasData
                    }

                    StateNotice {
                        message: root.errorTitle() + (zabbix.lastError !== "" ? ": " + zabbix.lastError : ".")
                        tone: root.urgent
                        visible: zabbix.lastError !== ""
                    }

                    StateNotice {
                        message: "The configured problem limit was reached. More matching problems may exist."
                        tone: root.urgent
                        visible: zabbix.truncated && zabbix.hasData
                    }

                    StateNotice {
                        message: "Waiting for the first problem refresh."
                        tone: root.dim
                        visible: zabbix.configured && !zabbix.loading && !zabbix.hasData && zabbix.lastError === ""
                    }

                    PanelSeparator {
                        foreground: root.foreground
                    }

                    Column {
                        width: parent.width
                        spacing: Style.space(8)

                        PanelSectionHeader {
                            text: "SEVERITIES"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }

                        Flow {
                            width: parent.width
                            spacing: Style.space(6)

                            Repeater {
                                id: severityRepeater
                                model: Model.SEVERITIES

                                SeverityControl {
                                    required property var modelData
                                    required property int index
                                    definition: modelData
                                    controlIndex: index
                                }
                            }
                        }
                    }

                    PanelSeparator {
                        foreground: root.foreground
                    }

                    Item {
                        width: parent.width
                        implicitHeight: Math.max(problemsHeader.implicitHeight, freshness.implicitHeight)

                        PanelSectionHeader {
                            id: problemsHeader
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "PROBLEMS · " + root.visibleProblems.length
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }

                        Text {
                            id: freshness
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: zabbix.lastUpdatedMs > 0 ? root.freshnessText() : ""
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    Text {
                        visible: zabbix.hasData && root.visibleProblems.length === 0
                        width: parent.width
                        text: "No unresolved problems match the selected severities."
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Column {
                        id: problemColumn
                        visible: zabbix.hasData && root.visibleProblems.length > 0
                        width: parent.width
                        spacing: Style.space(4)

                        Repeater {
                            id: problemRepeater
                            model: root.visibleProblems

                            ProblemRow {
                                required property var modelData
                                required property int index
                                width: problemColumn.width
                                problem: modelData
                                rowIndex: index
                            }
                        }
                    }

                    Text {
                        visible: zabbix.configured
                        width: parent.width
                        text: "↑↓/j/k navigate · enter toggle severity · r refresh · esc close · tab switch panel"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    component StateNotice: BorderSurface {
        id: notice
        property string message: ""
        property color tone: root.foreground

        width: parent ? parent.width : implicitWidth
        implicitHeight: noticeText.implicitHeight + Style.space(16)
        color: Style.normalFillFor(tone, Color.accent)
        borderSpec: Border.controlSpec("normal", tone, Color.accent)
        radius: Style.cornerRadius

        Text {
            id: noticeText
            anchors.fill: parent
            anchors.margins: Style.space(8)
            text: notice.message
            color: notice.tone
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }
    }

    component SeverityControl: Button {
        id: severityControl
        property var definition: null
        property int controlIndex: 0
        readonly property bool chosen: definition ? root.severitySelected(definition.value) : false

        text: definition ? root.severityLabel(definition) : ""
        iconText: chosen ? "󰄬" : ""
        selected: chosen
        bordered: true
        hasCursor: root.cursorActive && root.cursorIndex === controlIndex
        foreground: definition ? definition.color : root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        iconSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)

        onHovered: function (hovered) {
            if (hovered)
                root.setCursor(controlIndex);
        }
        onClicked: if (definition)
            root.toggleSeverity(definition.value)
    }

    component ProblemRow: CursorSurface {
        id: problemRow
        property var problem: null
        property int rowIndex: 0
        readonly property int navigationIndex: Model.SEVERITIES.length + rowIndex
        readonly property var severity: Model.severityDefinition(root.problemSeverity(problem))

        hasCursor: root.cursorActive && root.cursorIndex === navigationIndex
        foreground: root.foreground
        implicitHeight: problemContent.implicitHeight + Style.space(18)

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.space(4)
            radius: Math.min(Style.cornerRadius, width / 2)
            color: problemRow.severity ? problemRow.severity.color : root.dim
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.setCursor(problemRow.navigationIndex)
            onClicked: root.setCursor(problemRow.navigationIndex)
        }

        Column {
            id: problemContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(4)

            RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Text {
                    Layout.fillWidth: true
                    text: problemRow.severity ? root.severityLabel(problemRow.severity) : "Unknown severity"
                    color: problemRow.severity ? problemRow.severity.color : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: root.ageText(problemRow.problem ? problemRow.problem.clock : 0)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
            }

            Text {
                width: parent.width
                text: problemRow.problem ? String(problemRow.problem.name || "Unnamed problem") : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: root.hostsText(problemRow.problem)
                color: text === "Hosts unavailable" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
            }

            Row {
                visible: acknowledged.visible || suppressed.visible
                spacing: Style.space(8)

                Text {
                    id: acknowledged
                    visible: problemRow.problem && problemRow.problem.acknowledged === true
                    text: "ACKNOWLEDGED"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }

                Text {
                    id: suppressed
                    visible: problemRow.problem && problemRow.problem.suppressed === true
                    text: "SUPPRESSED"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }
            }
        }
    }
}
