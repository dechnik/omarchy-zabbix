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

    // Disclosure state is deliberately panel-local and resets on every open:
    // the panel exists to show problems, so the chrome starts out of the way.
    property bool noticesExpanded: false
    property bool filtersExpanded: false

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color barTextColor: bar ? bar.barForeground : Color.foreground
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property color dim: Qt.darker(foreground, 1.5)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property bool vertical: bar ? bar.vertical : false

    readonly property var selectedSeverities: Model.parseSeveritySelection(zabbix.selectedSeverities)
    readonly property string acknowledgement: zabbix.acknowledgement
    readonly property bool acknowledgedByMe: zabbix.acknowledgedByMeSetting
    readonly property bool acknowledgedByMeEnabled: acknowledgement === "acknowledged"
    readonly property bool showSuppressed: zabbix.showSuppressed
    readonly property bool showSymptoms: zabbix.showSymptoms
    readonly property var visibleProblems: Model.sortProblems(Model.filterProblems(zabbix.problems, selectedSeverities, acknowledgement))
    readonly property var summary: Model.severitySummary(zabbix.problems, selectedSeverities, zabbix.hasData, zabbix.truncated, acknowledgement)
    readonly property int summaryCount: summaryNumber()
    readonly property int summarySeverityValue: summaryValue()
    readonly property var summarySeverity: summarySeverityValue >= 0 ? Model.severityDefinition(summarySeverityValue) : null
    readonly property bool summaryAvailable: zabbix.hasData && (!summary || summary.available !== false)
    readonly property color summaryColor: summaryAvailable && summaryCount > 0 && summarySeverity ? summarySeverity.color : dim
    readonly property var notices: noticeList()
    readonly property bool hasNotices: notices.length > 0
    // An unconfigured widget has nothing else to show, so its setup notice is
    // never worth hiding behind a count.
    readonly property bool noticesOpen: hasNotices && (noticesExpanded || !zabbix.configured)

    readonly property int noticesCursorIndex: hasNotices ? 0 : -1
    readonly property int filtersCursorIndex: hasNotices ? 1 : 0
    readonly property int severityCursorBase: filtersCursorIndex + 1
    readonly property int acknowledgementCursorBase: severityCursorBase + Model.SEVERITIES.length
    readonly property int acknowledgedByMeCursorIndex: acknowledgementCursorBase + Model.ACKNOWLEDGEMENTS.length
    readonly property int showSuppressedCursorIndex: acknowledgedByMeCursorIndex + 1
    readonly property int showSymptomsCursorIndex: showSuppressedCursorIndex + 1
    readonly property int problemCursorBase: filtersExpanded ? showSymptomsCursorIndex + 1 : severityCursorBase
    readonly property int cursorCount: problemCursorBase + visibleProblems.length
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

    function severityShortLabel(definition) {
        if (!definition)
            return "?";
        return String(definition.short !== undefined ? definition.short : severityLabel(definition));
    }

    // Actionable state only. Progress ("connecting", "loading problems") is
    // already on the hero meta line and the bar glyph, so it earns no banner.
    function noticeList() {
        var list = [];
        if (!zabbix.configured)
            list.push({
                message: "Configure the Zabbix HTTPS URL and API token file in this widget's settings.",
                urgent: false
            });
        if (zabbix.lastError !== "")
            list.push({
                message: errorTitle() + ": " + zabbix.lastError,
                urgent: true
            });
        if (zabbix.stale && zabbix.hasData)
            list.push({
                message: "Showing the last complete result because the latest refresh failed.",
                urgent: true
            });
        if (zabbix.acknowledgedByMe && zabbix.identityError !== "")
            list.push({
                message: "Zabbix did not identify the API token's user, so the acknowledged-by-me filter is not applied. Permit user.checkAuthentication for the token's role. " + zabbix.identityError,
                urgent: true
            });
        if (zabbix.truncated && zabbix.hasData)
            list.push({
                message: "The configured problem limit was reached. More matching problems may exist.",
                urgent: true
            });
        if (zabbix.insecureTls)
            list.push({
                message: "TLS certificate verification is disabled. The API token and monitoring data may be intercepted.",
                urgent: true
            });
        return list;
    }

    function noticeSummary() {
        var count = notices.length;
        return count + (count === 1 ? " warning" : " warnings");
    }

    function noticesUrgent() {
        for (var i = 0; i < notices.length; i++)
            if (notices[i].urgent)
                return true;
        return false;
    }

    function severitySelected(value) {
        return selectedSeverities.indexOf(Number(value)) !== -1;
    }

    function writeSettings(patch) {
        var entry = {
            id: moduleName
        };
        for (var key in settings)
            if (key !== "id")
                entry[key] = settings[key];
        for (var changed in patch)
            entry[changed] = patch[changed];
        settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline(moduleName, entry);
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

        root.writeSettings({
            severities: next.map(function (value) {
                return String(value);
            })
        });
    }

    // The settings form stores an enum option's label, so the panel writes the
    // same label form back rather than the internal lowercase value.
    function setAcknowledgement(value) {
        var next = Model.parseAcknowledgement(value);
        if (next === acknowledgement)
            return;
        root.writeSettings({
            acknowledgement: Model.persistAcknowledgement(next)
        });
    }

    function toggleShowSuppressed() {
        root.writeSettings({
            showSuppressed: !showSuppressed
        });
    }

    function toggleShowSymptoms() {
        root.writeSettings({
            showSymptoms: !showSymptoms
        });
    }

    function toggleAcknowledgedByMe() {
        if (!acknowledgedByMeEnabled)
            return;
        root.writeSettings({
            acknowledgedByMe: !acknowledgedByMe
        });
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
            if (phase === "identify_user" || phase === "identifying-user")
                return "Identifying the API token's user";
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
        parts.push("ack=" + root.acknowledgement);
        if (zabbix.acknowledgedByMe)
            parts.push("ack-by-me");
        if (zabbix.acknowledgedByMe && zabbix.identityError !== "")
            parts.push("identity-unavailable");
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
        if (hasNotices && cursorIndex === noticesCursorIndex) {
            noticesExpanded = !noticesExpanded;
            return;
        }
        if (cursorIndex === filtersCursorIndex) {
            filtersExpanded = !filtersExpanded;
            return;
        }
        // Collapsed filters contribute no cursor stops; everything past the
        // header is a read-only problem row.
        if (!filtersExpanded)
            return;
        if (cursorIndex >= severityCursorBase && cursorIndex < acknowledgementCursorBase) {
            toggleSeverity(Model.SEVERITIES[cursorIndex - severityCursorBase].value);
            return;
        }
        if (cursorIndex >= acknowledgementCursorBase && cursorIndex < acknowledgedByMeCursorIndex) {
            setAcknowledgement(Model.ACKNOWLEDGEMENTS[cursorIndex - acknowledgementCursorBase].value);
            return;
        }
        if (cursorIndex === acknowledgedByMeCursorIndex) {
            toggleAcknowledgedByMe();
            return;
        }
        if (cursorIndex === showSuppressedCursorIndex) {
            toggleShowSuppressed();
            return;
        }
        if (cursorIndex === showSymptomsCursorIndex)
            toggleShowSymptoms();
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
        if (cursorIndex >= problemCursorBase) {
            scrollItemIntoView(problemRepeater.itemAt(cursorIndex - problemCursorBase));
            return;
        }
        if (hasNotices && cursorIndex === noticesCursorIndex) {
            scrollItemIntoView(noticesHeader);
            return;
        }
        if (cursorIndex === filtersCursorIndex) {
            scrollItemIntoView(filtersHeader);
            return;
        }
        if (cursorIndex < acknowledgementCursorBase)
            scrollItemIntoView(severityRepeater.itemAt(cursorIndex - severityCursorBase));
        else if (cursorIndex < acknowledgedByMeCursorIndex)
            scrollItemIntoView(acknowledgementGroup);
        else if (cursorIndex === acknowledgedByMeCursorIndex)
            scrollItemIntoView(acknowledgedByMeControl);
        else
            scrollItemIntoView(includeRow);
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onOpenedChanged: if (opened) {
        cursorActive = false;
        cursorIndex = 0;
        noticesExpanded = false;
        filtersExpanded = false;
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

                    DisclosureHeader {
                        id: noticesHeader
                        visible: root.hasNotices
                        label: root.noticeSummary()
                        glyph: root.noticesUrgent() ? "󰀦" : ""
                        tone: root.noticesUrgent() ? root.urgent : root.dim
                        expanded: root.noticesOpen
                        // Forced open while unconfigured; no point offering a toggle.
                        toggleable: zabbix.configured
                        cursorTargetIndex: root.noticesCursorIndex
                        onToggled: root.noticesExpanded = !root.noticesExpanded
                    }

                    Column {
                        width: parent.width
                        visible: root.noticesOpen
                        spacing: Style.space(8)

                        Repeater {
                            model: root.notices

                            StateNotice {
                                required property var modelData
                                message: String(modelData.message)
                                tone: modelData.urgent === true ? root.urgent : root.dim
                            }
                        }
                    }

                    PanelSeparator {
                        foreground: root.foreground
                    }

                    DisclosureHeader {
                        id: filtersHeader
                        label: "FILTERS"
                        tone: root.dim
                        expanded: root.filtersExpanded
                        cursorTargetIndex: root.filtersCursorIndex
                        onToggled: root.filtersExpanded = !root.filtersExpanded
                    }

                    Column {
                        id: filtersContent
                        width: parent.width
                        visible: root.filtersExpanded
                        spacing: Style.space(6)

                        // Indented one step under the FILTERS header so the two
                        // captioned groups read as its contents, not as peers.
                        readonly property real indent: Style.space(10)

                        FilterGroupLabel {
                            x: filtersContent.indent
                            text: "Severity"
                        }

                        Flow {
                            x: filtersContent.indent
                            width: filtersContent.width - filtersContent.indent
                            spacing: Style.space(6)

                            Repeater {
                                id: severityRepeater
                                model: Model.SEVERITIES

                                SeverityControl {
                                    required property var modelData
                                    required property int index
                                    definition: modelData
                                    controlIndex: root.severityCursorBase + index
                                }
                            }
                        }

                        FilterGroupLabel {
                            x: filtersContent.indent
                            topPadding: Style.space(6)
                            text: "Acknowledgement"
                        }

                        ButtonGroup {
                            id: acknowledgementGroup
                            x: filtersContent.indent
                            options: Model.ACKNOWLEDGEMENTS
                            value: root.acknowledgement
                            foreground: root.foreground
                            accent: Color.accent
                            fontFamily: root.fontFamily
                            fontSize: Style.font.bodySmall
                            focusable: false
                            cursorIndex: root.cursorActive ? root.cursorIndex - root.acknowledgementCursorBase : -1

                            onChanged: function (value) {
                                root.setAcknowledgement(value);
                            }
                            onHovered: function (index, isHovered) {
                                if (isHovered)
                                    root.setCursor(root.acknowledgementCursorBase + index);
                            }
                        }

                        Button {
                            id: acknowledgedByMeControl
                            x: filtersContent.indent
                            text: "Only acknowledged by me"
                            iconText: root.acknowledgedByMe ? "󰄬" : ""
                            selected: root.acknowledgedByMe && root.acknowledgedByMeEnabled
                            bordered: true
                            hasCursor: root.cursorActive && root.cursorIndex === root.acknowledgedByMeCursorIndex
                            enabled: root.acknowledgedByMeEnabled
                            // Button paints no disabled state of its own.
                            opacity: enabled ? 1 : 0.45
                            tooltipText: root.acknowledgedByMeEnabled ? "Show only problems you acknowledged" : "Select Acknowledged to use this filter"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.bodySmall
                            iconSize: Style.font.bodySmall
                            horizontalPadding: Style.space(8)
                            verticalPadding: Style.space(5)

                            onHovered: function (hovered) {
                                if (hovered)
                                    root.setCursor(root.acknowledgedByMeCursorIndex);
                            }
                            onClicked: root.toggleAcknowledgedByMe()
                        }

                        FilterGroupLabel {
                            x: filtersContent.indent
                            topPadding: Style.space(6)
                            text: "Include"
                        }

                        Row {
                            id: includeRow
                            x: filtersContent.indent
                            spacing: Style.space(6)

                            IncludeControl {
                                label: "Suppressed"
                                chosen: root.showSuppressed
                                controlIndex: root.showSuppressedCursorIndex
                                onToggled: root.toggleShowSuppressed()
                            }

                            IncludeControl {
                                label: "Symptoms"
                                chosen: root.showSymptoms
                                controlIndex: root.showSymptomsCursorIndex
                                onToggled: root.toggleShowSymptoms()
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
                        text: "No unresolved problems match the selected filters."
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
                        text: "↑↓/j/k navigate · enter expand or toggle · r refresh · esc close · tab switch panel"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }

    component FilterGroupLabel: Text {
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
    }

    component DisclosureHeader: CursorSurface {
        id: disclosure
        property string label: ""
        property string glyph: ""
        property color tone: root.dim
        property bool expanded: false
        property bool toggleable: true
        property int cursorTargetIndex: -1

        signal toggled

        width: parent ? parent.width : implicitWidth
        hasCursor: root.cursorActive && cursorTargetIndex >= 0 && root.cursorIndex === cursorTargetIndex
        foreground: root.foreground
        implicitHeight: disclosureLabel.implicitHeight + Style.space(12)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: disclosure.toggleable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: if (disclosure.cursorTargetIndex >= 0)
                root.setCursor(disclosure.cursorTargetIndex)
            onClicked: if (disclosure.toggleable)
                disclosure.toggled()
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
                visible: disclosure.glyph !== ""
                text: disclosure.glyph
                color: disclosure.tone
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: disclosureLabel
                text: disclosure.label
                color: disclosure.tone
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            visible: disclosure.toggleable
            text: disclosure.expanded ? "󰅀" : "󰅂"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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

    component IncludeControl: Button {
        property string label: ""
        property bool chosen: false
        property int controlIndex: 0

        signal toggled

        text: label
        iconText: chosen ? "󰄬" : ""
        selected: chosen
        bordered: true
        hasCursor: root.cursorActive && root.cursorIndex === controlIndex
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        iconSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)

        onHovered: function (hovered) {
            if (hovered)
                root.setCursor(controlIndex);
        }
        onClicked: toggled()
    }

    component SeverityControl: Button {
        id: severityControl
        property var definition: null
        property int controlIndex: 0
        readonly property bool chosen: definition ? root.severitySelected(definition.value) : false

        text: definition ? root.severityShortLabel(definition) : ""
        tooltipText: definition ? root.severityLabel(definition) : ""
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
        readonly property int navigationIndex: root.problemCursorBase + rowIndex
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
