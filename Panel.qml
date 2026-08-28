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

    // Expand state is deliberately panel-local and resets on every open: the
    // panel exists to show problems, so the chrome starts out of the way.
    property bool expanded: false

    // Which server row has its editor open, as an accordion. Panel-local like
    // `expanded`, and reset on every open.
    property int editingServerIndex: -1
    // A focused TextField or spin box must receive keys itself, so the panel's
    // key catcher stands down while one owns the keyboard.
    property int editorFocusCount: 0
    readonly property bool editingField: editorFocusCount > 0

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color barTextColor: bar ? bar.barForeground : Color.foreground
    readonly property color urgent: bar ? bar.urgent : Color.urgent
    readonly property color dim: Qt.darker(foreground, 1.5)
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property bool vertical: bar ? bar.vertical : false

    readonly property var servers: zabbix.servers
    // Repeaters key on the stable id list, not on the server objects: editing
    // a name must update one row's bindings, not rebuild every delegate and
    // destroy the very field being typed into.
    readonly property var serverIdList: zabbix.serverIdList
    readonly property var selectedServerIds: zabbix.selectedServerIds
    readonly property bool multiServer: zabbix.multiServer
    readonly property var selectedSeverities: Model.parseSeveritySelection(zabbix.selectedSeverities)
    readonly property string acknowledgement: zabbix.acknowledgement
    readonly property bool acknowledgedByMe: zabbix.acknowledgedByMeSetting
    readonly property bool acknowledgedByMeEnabled: acknowledgement === "acknowledged"
    readonly property bool showSuppressed: zabbix.showSuppressed
    readonly property bool showSymptoms: zabbix.showSymptoms
    readonly property bool showUnmonitored: zabbix.showUnmonitored
    readonly property var visibleProblems: Model.sortProblems(Model.filterProblems(zabbix.problems, selectedSeverities, acknowledgement))
    readonly property var summary: Model.severitySummary(zabbix.problems, selectedSeverities, zabbix.hasData, zabbix.truncated, acknowledgement)
    readonly property int summaryCount: summaryNumber()
    readonly property int summarySeverityValue: summaryValue()
    readonly property var summarySeverity: summarySeverityValue >= 0 ? Model.severityDefinition(summarySeverityValue) : null
    readonly property bool summaryAvailable: zabbix.hasData && (!summary || summary.available !== false)
    readonly property color summaryColor: summaryAvailable && summaryCount > 0 && summarySeverity ? summarySeverity.color : dim
    readonly property var notices: noticeList()
    readonly property bool hasNotices: notices.length > 0

    // The cursor walks the expanded panel in the order it is drawn: the server
    // editor, then the filters, then the refresh interval, then the problems.
    // An open editor inserts its two own stops directly after its server row.
    readonly property int serverEditorCursorBase: 0
    readonly property int insecureTlsCursorIndex: editingServerIndex >= 0 ? serverEditorCursorBase + editingServerIndex + 1 : -1
    readonly property int removeServerCursorIndex: editingServerIndex >= 0 ? insecureTlsCursorIndex + 1 : -1
    readonly property int addServerCursorIndex: serverEditorCursorBase + servers.length + (editingServerIndex >= 0 ? 2 : 0)
    readonly property int serverFilterCursorBase: addServerCursorIndex + 1
    readonly property int severityCursorBase: serverFilterCursorBase + (multiServer ? servers.length : 0)
    readonly property int acknowledgementCursorBase: severityCursorBase + Model.SEVERITIES.length
    readonly property int acknowledgedByMeCursorIndex: acknowledgementCursorBase + Model.ACKNOWLEDGEMENTS.length
    readonly property int showSuppressedCursorIndex: acknowledgedByMeCursorIndex + 1
    readonly property int showSymptomsCursorIndex: showSuppressedCursorIndex + 1
    readonly property int showUnmonitoredCursorIndex: showSymptomsCursorIndex + 1
    readonly property int refreshIntervalCursorIndex: showUnmonitoredCursorIndex + 1
    readonly property int problemCursorBase: expanded ? refreshIntervalCursorIndex + 1 : 0
    readonly property int cursorCount: problemCursorBase + visibleProblems.length
    // Refreshing is routine background noise; only stale data earns a bar glyph.
    readonly property string activityGlyph: zabbix.stale ? "󰅖" : ""
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
        if (servers.length === 0) {
            list.push({
                message: "No Zabbix server is configured. Add one in the SERVERS section below.",
                urgent: false
            });
            return list;
        }

        // Every message names its server once more than one is configured;
        // an unprefixed warning would be unactionable in a merged list.
        var states = zabbix.serverStates;
        for (var i = 0; i < states.length; i++) {
            var state = states[i];
            if (selectedServerIds.indexOf(String(state.id)) < 0)
                continue;
            var prefix = multiServer ? String(state.label) + ": " : "";
            if (state.configured !== true) {
                var reason = String(state.endpointError || "") !== "" ? String(state.endpointError) : "API token file is not configured";
                list.push({
                    message: prefix + reason + ". Configure it in the SERVERS section below.",
                    urgent: false
                });
                continue;
            }
            if (String(state.lastError || "") !== "")
                list.push({
                    message: prefix + errorTitle(state.errorCategory) + ": " + state.lastError,
                    urgent: true
                });
            if (state.stale === true && state.hasData === true)
                list.push({
                    message: prefix + "Showing the last complete result because the latest refresh failed.",
                    urgent: true
                });
            if (zabbix.acknowledgedByMe && String(state.identityError || "") !== "")
                list.push({
                    message: prefix + "Zabbix did not identify the API token's user, so the acknowledged-by-me filter is not applied. Permit user.checkAuthentication for the token's role. " + state.identityError,
                    urgent: true
                });
            if (state.truncated === true && state.hasData === true)
                list.push({
                    message: prefix + "The configured problem limit was reached. More matching problems may exist.",
                    urgent: true
                });
            if (state.insecureTls === true)
                list.push({
                    message: prefix + "TLS certificate verification is disabled. The API token and monitoring data may be intercepted.",
                    urgent: true
                });
        }
        return list;
    }

    function severitySelected(value) {
        return selectedSeverities.indexOf(Number(value)) !== -1;
    }

    // `removeKeys` exists so writing the server list can also drop the
    // pre-servers connection keys, leaving one source of truth behind.
    function writeSettings(patch, removeKeys) {
        var drop = {};
        for (var d = 0; d < (removeKeys || []).length; d++)
            drop[removeKeys[d]] = true;
        var entry = {
            id: moduleName
        };
        for (var key in settings)
            if (key !== "id" && !drop[key])
                entry[key] = settings[key];
        for (var changed in patch)
            entry[changed] = patch[changed];
        settings = entry;
        if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
            bar.shell.updateEntryInline(moduleName, entry);
    }

    readonly property var legacyConnectionKeys: ["url", "endpoint", "tokenFile", "caCertificateFile", "insecureTls"]

    function serverEntries() {
        return Model.persistServers(servers);
    }

    function writeServers(list, selection) {
        var patch = {
            servers: Model.persistServers(list)
        };
        if (selection !== undefined)
            patch.selectedServers = selection;
        root.writeSettings(patch, legacyConnectionKeys);
    }

    function updateServer(index, patch) {
        var list = serverEntries();
        if (index < 0 || index >= list.length)
            return;
        for (var key in patch)
            list[index][key] = patch[key];
        writeServers(list);
    }

    function addServer() {
        var list = serverEntries();
        var id = Model.newServerId(list);
        list.push({
            id: id,
            name: "",
            url: "",
            tokenFile: Model.DEFAULT_TOKEN_FILE,
            caCertificateFile: "",
            insecureTls: false
        });
        var selection = selectedServerIds.slice();
        selection.push(id);
        writeServers(list, selection);
        editingServerIndex = list.length - 1;
    }

    function removeServer(index) {
        var list = serverEntries();
        if (index < 0 || index >= list.length)
            return;
        var removedId = list[index].id;
        list.splice(index, 1);
        var selection = [];
        for (var i = 0; i < selectedServerIds.length; i++)
            if (selectedServerIds[i] !== removedId)
                selection.push(selectedServerIds[i]);
        editingServerIndex = -1;
        writeServers(list, selection);
    }

    function toggleServerEditor(index) {
        editingServerIndex = editingServerIndex === index ? -1 : index;
    }

    function toggleServer(id) {
        root.writeSettings({
            selectedServers: Model.toggleServerSelection(selectedServerIds, id, servers)
        });
    }

    function serverSelected(id) {
        return selectedServerIds.indexOf(String(id)) !== -1;
    }

    function setRefreshInterval(value) {
        var next = Math.round(Number(value));
        if (!isFinite(next))
            return;
        next = Math.max(Model.MIN_REFRESH_INTERVAL_SEC, Math.min(Model.MAX_REFRESH_INTERVAL_SEC, next));
        if (next === zabbix.refreshIntervalSec)
            return;
        root.writeSettings({
            refreshIntervalSec: next
        });
    }

    // Cursor stops for the server rows renumber around the open editor's own
    // two stops, so the walk order always matches what is on screen.
    function serverRowForCursor(index) {
        var offset = index - serverEditorCursorBase;
        if (offset < 0 || index >= addServerCursorIndex)
            return -1;
        if (editingServerIndex < 0)
            return offset;
        if (offset <= editingServerIndex)
            return offset;
        if (offset <= editingServerIndex + 2)
            return -1;
        return offset - 2;
    }

    function cursorForServerRow(row) {
        if (editingServerIndex >= 0 && row > editingServerIndex)
            return serverEditorCursorBase + row + 2;
        return serverEditorCursorBase + row;
    }

    function beginFieldEdit() {
        editorFocusCount += 1;
    }

    function endFieldEdit() {
        editorFocusCount = Math.max(0, editorFocusCount - 1);
    }

    function releaseFieldFocus() {
        Qt.callLater(function () {
            if (keyCatcher)
                keyCatcher.forceActiveFocus();
        });
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

    function toggleShowUnmonitored() {
        root.writeSettings({
            showUnmonitored: !showUnmonitored
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

    // Crossing Service's `property var problems` turns the nested host arrays
    // into QVariantList wrappers, which fail Array.isArray while still
    // indexing like an array — so this counts rather than type-checks.
    function hostsText(problem) {
        var hosts = problem && problem.hosts ? problem.hosts : [];
        var count = Number(hosts.length);
        if (!isFinite(count) || count < 0)
            count = 0;
        var names = [];
        for (var i = 0; i < count; i++) {
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
        // Partial is its own state: some servers answered and some did not, so
        // the count is real but incomplete.
        if (zabbix.partial)
            return "Partial data";
        if (zabbix.stale)
            return "Stale data";
        if (zabbix.hasData)
            return zabbix.insecureTls ? "Connected insecurely" : "Connected";
        return "Waiting for data";
    }

    function headerMeta() {
        var parts = [connectionLabel()];
        // A merged list has no single Zabbix version to name, so the server
        // tally takes that slot instead.
        if (multiServer)
            parts.push(zabbix.connectedCount + "/" + servers.length + " servers connected");
        else if (String(zabbix.serverVersion || "") !== "")
            parts.push("Zabbix " + zabbix.serverVersion);
        if (zabbix.lastUpdatedMs > 0)
            parts.push(freshnessText());
        return parts.join(" · ");
    }

    function errorTitle(category) {
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
        return labels[String(category !== undefined ? category : zabbix.errorCategory || "")] || "Request failed";
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
        if (multiServer)
            parts.push("across " + selectedServerIds.length + " of " + servers.length + " servers");
        if (zabbix.failingCount > 0)
            parts.push(zabbix.failingCount + " server" + (zabbix.failingCount === 1 ? "" : "s") + " failing");
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

    // Deliberately free of URLs, host names, and server names: this string is
    // handed out over IPC.
    function sanitizedStatus() {
        if (!zabbix.configured)
            return "zabbix setup-required servers=" + servers.length;
        if (!zabbix.hasData) {
            if (zabbix.loading)
                return "zabbix connecting servers=" + servers.length;
            return "zabbix unavailable servers=" + servers.length + " category=" + safeErrorCategory();
        }

        var parts = ["zabbix"];
        parts.push("servers=" + servers.length);
        parts.push("selected=" + selectedServerIds.length);
        if (zabbix.failingCount > 0)
            parts.push("failing=" + zabbix.failingCount);
        if (zabbix.partial)
            parts.push("partial");
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
        // Collapsed, every cursor stop is a read-only problem row.
        if (!expanded)
            return;
        if (cursorIndex === addServerCursorIndex) {
            addServer();
            return;
        }
        if (cursorIndex === insecureTlsCursorIndex) {
            updateServer(editingServerIndex, {
                insecureTls: !servers[editingServerIndex].insecureTls
            });
            return;
        }
        if (cursorIndex === removeServerCursorIndex) {
            removeServer(editingServerIndex);
            return;
        }
        if (cursorIndex < serverFilterCursorBase) {
            var row = serverRowForCursor(cursorIndex);
            if (row >= 0)
                toggleServerEditor(row);
            return;
        }
        if (cursorIndex < severityCursorBase) {
            toggleServer(servers[cursorIndex - serverFilterCursorBase].id);
            return;
        }
        if (cursorIndex === refreshIntervalCursorIndex) {
            refreshIntervalField.field.forceActiveFocus();
            return;
        }
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
        if (cursorIndex === showSymptomsCursorIndex) {
            toggleShowSymptoms();
            return;
        }
        if (cursorIndex === showUnmonitoredCursorIndex)
            toggleShowUnmonitored();
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
        if (cursorIndex === refreshIntervalCursorIndex) {
            scrollItemIntoView(refreshIntervalField);
            return;
        }
        if (cursorIndex === addServerCursorIndex) {
            scrollItemIntoView(addServerButton);
            return;
        }
        if (cursorIndex < serverFilterCursorBase) {
            var row = serverRowForCursor(cursorIndex);
            scrollItemIntoView(serverRepeater.itemAt(row >= 0 ? row : editingServerIndex));
            return;
        }
        if (cursorIndex < severityCursorBase) {
            scrollItemIntoView(serverFilterRepeater.itemAt(cursorIndex - serverFilterCursorBase));
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
        editingServerIndex = -1;
        editorFocusCount = 0;
        // Unconfigured widgets have nothing else to show, so their setup
        // notice is never worth hiding behind the Expand button.
        expanded = !zabbix.configured;
        nowMs = Date.now();
        if (panelFlick)
            panelFlick.contentY = 0;
        if (zabbix.configured && (!zabbix.hasData || zabbix.stale))
            zabbix.refresh();
    }
    onCursorCountChanged: clampCursor()

    Servers {
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
        dimmed: !root.summaryAvailable || zabbix.stale
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
        contentWidth: panel.fittedContentWidth(Style.space(root.expanded ? 700 : 430))
        contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(root.expanded ? 820 : 640))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            // A focused server field or spin box must receive its own keys,
            // including the r/e shortcuts and j/k, so this stands down.
            blocked: root.editingField

            onMoveRequested: function (dx, dy) {
                root.moveCursor(dx, dy);
            }
            onActivateRequested: root.activateCursor()
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }
            onTextKey: function (text) {
                var key = String(text).toLowerCase();
                if (key === "r")
                    zabbix.refresh(true);
                else if (key === "e")
                    root.expanded = !root.expanded;
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
                                Row {
                                    spacing: Style.space(4)

                                    PanelActionButton {
                                        iconText: "󰑐"
                                        tooltipText: "Refresh Zabbix problems  (r)"
                                        foreground: hero.foreground
                                        fontFamily: hero.fontFamily
                                        enabled: !heroBox.busy
                                        onClicked: heroBox.refresh()
                                    }

                                    PanelActionButton {
                                        iconText: root.expanded ? "󰊔" : "󰊓"
                                        tooltipText: root.expanded ? "Show only problems  (e)" : "Show warnings, filters, and more  (e)"
                                        foreground: hero.foreground
                                        fontFamily: hero.fontFamily
                                        onClicked: root.expanded = !root.expanded
                                    }
                                }
                            }
                        }
                    }

                    PanelSeparator {
                        foreground: root.foreground
                    }

                    PanelSectionHeader {
                        visible: root.expanded && root.hasNotices
                        text: "WARNINGS · " + root.notices.length
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }

                    Column {
                        width: parent.width
                        visible: root.expanded && root.hasNotices
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
                        visible: root.expanded && root.hasNotices
                        foreground: root.foreground
                    }

                    PanelSectionHeader {
                        visible: root.expanded
                        text: "SERVERS · " + root.servers.length
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }

                    Column {
                        id: serversContent
                        width: parent.width
                        visible: root.expanded
                        spacing: Style.space(6)

                        readonly property real indent: Style.space(10)

                        Text {
                            visible: root.servers.length === 0
                            width: serversContent.width
                            text: "No Zabbix server is configured yet. Add one to start polling."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            id: serverRepeater
                            model: root.serverIdList

                            ServerRow {
                                required property var modelData
                                required property int index
                                width: serversContent.width
                                server: zabbix.serverFor(modelData)
                                rowIndex: index
                            }
                        }

                        Button {
                            id: addServerButton
                            x: serversContent.indent
                            text: "Add server"
                            iconText: "󰐕"
                            bordered: true
                            hasCursor: root.cursorActive && root.cursorIndex === root.addServerCursorIndex
                            tooltipText: "Add another Zabbix server to poll"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.bodySmall
                            iconSize: Style.font.bodySmall
                            horizontalPadding: Style.space(8)
                            verticalPadding: Style.space(5)

                            onHovered: function (hovered) {
                                if (hovered)
                                    root.setCursor(root.addServerCursorIndex);
                            }
                            onClicked: root.addServer()
                        }
                    }

                    PanelSeparator {
                        visible: root.expanded
                        foreground: root.foreground
                    }

                    PanelSectionHeader {
                        visible: root.expanded
                        text: "FILTERS"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }

                    Column {
                        id: filtersContent
                        width: parent.width
                        visible: root.expanded
                        spacing: Style.space(6)

                        // Indented one step under the FILTERS header so the two
                        // captioned groups read as its contents, not as peers.
                        readonly property real indent: Style.space(10)

                        // Only worth a row once there is something to choose
                        // between; one server needs no server filter.
                        FilterGroupLabel {
                            x: filtersContent.indent
                            visible: root.multiServer
                            text: "Server"
                        }

                        Flow {
                            x: filtersContent.indent
                            visible: root.multiServer
                            width: filtersContent.width - filtersContent.indent
                            spacing: Style.space(6)

                            Repeater {
                                id: serverFilterRepeater
                                model: root.multiServer ? root.serverIdList : []

                                ServerChip {
                                    required property var modelData
                                    required property int index
                                    server: zabbix.serverFor(modelData)
                                    controlIndex: root.serverFilterCursorBase + index
                                }
                            }
                        }

                        FilterGroupLabel {
                            x: filtersContent.indent
                            topPadding: root.multiServer ? Style.space(6) : 0
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

                            IncludeControl {
                                label: "Unmonitored"
                                chosen: root.showUnmonitored
                                controlIndex: root.showUnmonitoredCursorIndex
                                onToggled: root.toggleShowUnmonitored()
                            }
                        }
                    }

                    PanelSeparator {
                        visible: root.expanded
                        foreground: root.foreground
                    }

                    PanelSectionHeader {
                        visible: root.expanded
                        text: "MORE OPTIONS"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }

                    Column {
                        width: parent.width
                        visible: root.expanded
                        spacing: Style.space(6)

                        NumberField {
                            id: refreshIntervalField
                            x: Style.space(10)
                            label: "Refresh interval (seconds)"
                            from: Model.MIN_REFRESH_INTERVAL_SEC
                            to: Model.MAX_REFRESH_INTERVAL_SEC
                            stepSize: 15
                            value: zabbix.refreshIntervalSec
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            fontSize: Style.font.bodySmall
                            hasCursor: root.cursorActive && root.cursorIndex === root.refreshIntervalCursorIndex

                            onModified: function (value) {
                                root.setRefreshInterval(value);
                            }
                            onHovered: function (on) {
                                if (on)
                                    root.setCursor(root.refreshIntervalCursorIndex);
                            }

                            // Escape is not consumed by the spin box's own text
                            // input, so it propagates here and hands the panel
                            // its keyboard back.
                            Keys.onPressed: function (event) {
                                if (event.key !== Qt.Key_Escape)
                                    return;
                                root.setRefreshInterval(refreshIntervalField.field.value);
                                root.releaseFieldFocus();
                                event.accepted = true;
                            }
                        }

                        Connections {
                            target: refreshIntervalField.field

                            function onActiveFocusChanged() {
                                if (refreshIntervalField.field.activeFocus) {
                                    root.beginFieldEdit();
                                    return;
                                }
                                root.endFieldEdit();
                                root.setRefreshInterval(refreshIntervalField.field.value);
                            }
                        }

                        Text {
                            width: parent.width
                            text: "The problem limit and the remaining options live in this widget's settings."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
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
                        text: "↑↓/j/k navigate · enter toggle/edit · e expand/compact · r refresh · esc close or leave a field · tab switch panel"
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

    component ServerChip: Button {
        property var server: null
        property int controlIndex: 0
        readonly property bool chosen: server ? root.serverSelected(server.id) : false

        text: server ? String(server.label || "") : ""
        tooltipText: server ? (String(server.url || "") !== "" ? String(server.url) : "No URL configured") : ""
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
        onClicked: if (server)
            root.toggleServer(server.id)
    }

    // Typing breaks a declarative `text:` binding, so the stored value is
    // pushed in explicitly and only while the field is not being edited.
    component EditorField: Column {
        id: editorField
        property string label: ""
        property string sourceText: ""
        property string placeholder: ""

        signal committed(string value)

        spacing: Style.space(3)

        function commit() {
            if (input.text !== editorField.sourceText)
                editorField.committed(input.text);
        }

        onSourceTextChanged: if (!input.activeFocus)
            input.text = editorField.sourceText

        Text {
            text: editorField.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
        }

        TextField {
            id: input
            width: editorField.width
            placeholderText: editorField.placeholder
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            verticalPadding: Style.space(4)

            // Counted separately from activeFocus: a commit can rebuild this
            // row, and a field destroyed while focused would otherwise leave
            // the key catcher blocked for good.
            property bool counted: false

            Component.onCompleted: text = editorField.sourceText
            Component.onDestruction: if (counted) {
                counted = false;
                root.endFieldEdit();
            }

            onActiveFocusChanged: {
                if (activeFocus) {
                    if (counted)
                        return;
                    counted = true;
                    root.beginFieldEdit();
                    return;
                }
                if (!counted)
                    return;
                counted = false;
                root.endFieldEdit();
                editorField.commit();
            }

            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Escape) {
                    input.text = editorField.sourceText;
                    root.releaseFieldFocus();
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    editorField.commit();
                    root.releaseFieldFocus();
                    event.accepted = true;
                }
            }
        }
    }

    component ServerRow: Column {
        id: serverRow
        property var server: null
        property int rowIndex: 0
        readonly property bool editing: root.editingServerIndex === rowIndex
        readonly property int navigationIndex: root.cursorForServerRow(rowIndex)
        readonly property var serverState: serverRow.server ? zabbix.stateFor(String(serverRow.server.id)) : null
        readonly property color statusColor: {
            if (!serverRow.server || serverRow.server.configured !== true)
                return root.dim;
            if (!serverRow.serverState)
                return root.dim;
            if (String(serverRow.serverState.lastError || "") !== "")
                return root.urgent;
            if (serverRow.serverState.hasData === true)
                return Color.accent;
            return root.dim;
        }

        spacing: Style.space(6)

        CursorSurface {
            id: serverHeader
            width: serverRow.width
            hasCursor: root.cursorActive && root.cursorIndex === serverRow.navigationIndex
            foreground: root.foreground
            implicitHeight: headerRow.implicitHeight + Style.space(12)

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.setCursor(serverRow.navigationIndex)
                onClicked: {
                    root.setCursor(serverRow.navigationIndex);
                    root.toggleServerEditor(serverRow.rowIndex);
                }
            }

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                    text: serverRow.editing ? "󰅀" : "󰅂"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }

                Text {
                    text: "●"
                    color: serverRow.statusColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }

                Text {
                    text: serverRow.server ? String(serverRow.server.label || "") : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: Style.space(160)
                }

                Text {
                    Layout.fillWidth: true
                    text: serverRow.server && String(serverRow.server.url || "") !== "" ? String(serverRow.server.url) : "No URL configured"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        Column {
            id: serverEditor
            visible: serverRow.editing
            x: Style.space(10)
            width: serverRow.width - Style.space(20)
            spacing: Style.space(6)

            EditorField {
                width: serverEditor.width
                label: "Name"
                placeholder: "Optional label for this server"
                sourceText: serverRow.server ? String(serverRow.server.name || "") : ""
                onCommitted: function (value) {
                    root.updateServer(serverRow.rowIndex, {
                        name: value
                    });
                }
            }

            EditorField {
                width: serverEditor.width
                label: "Zabbix URL"
                placeholder: "https://zabbix.example.com/zabbix"
                sourceText: serverRow.server ? String(serverRow.server.url || "") : ""
                onCommitted: function (value) {
                    root.updateServer(serverRow.rowIndex, {
                        url: value
                    });
                }
            }

            Text {
                visible: serverRow.server && String(serverRow.server.endpointError || "") !== "" && String(serverRow.server.url || "") !== ""
                width: serverEditor.width
                text: serverRow.server ? String(serverRow.server.endpointError || "") : ""
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
            }

            EditorField {
                width: serverEditor.width
                label: "API token file"
                placeholder: Model.DEFAULT_TOKEN_FILE
                sourceText: serverRow.server ? String(serverRow.server.tokenFile || "") : ""
                onCommitted: function (value) {
                    root.updateServer(serverRow.rowIndex, {
                        tokenFile: value
                    });
                }
            }

            EditorField {
                width: serverEditor.width
                label: "Custom CA certificate"
                placeholder: "Optional PEM trust anchor"
                sourceText: serverRow.server ? String(serverRow.server.caCertificateFile || "") : ""
                onCommitted: function (value) {
                    root.updateServer(serverRow.rowIndex, {
                        caCertificateFile: value
                    });
                }
            }

            Row {
                width: serverEditor.width
                spacing: Style.space(6)

                Button {
                    text: "Disable TLS verification"
                    iconText: serverRow.server && serverRow.server.insecureTls === true ? "󰄬" : ""
                    selected: serverRow.server ? serverRow.server.insecureTls === true : false
                    bordered: true
                    hasCursor: root.cursorActive && root.cursorIndex === root.insecureTlsCursorIndex && serverRow.editing
                    tooltipText: "Unsafe fallback. Prefer a custom CA certificate."
                    foreground: serverRow.server && serverRow.server.insecureTls === true ? root.urgent : root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    iconSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(5)

                    onHovered: function (hovered) {
                        if (hovered && serverRow.editing)
                            root.setCursor(root.insecureTlsCursorIndex);
                    }
                    onClicked: root.updateServer(serverRow.rowIndex, {
                        insecureTls: !(serverRow.server && serverRow.server.insecureTls === true)
                    })
                }

                Button {
                    text: "Remove"
                    iconText: "󰆴"
                    bordered: true
                    hasCursor: root.cursorActive && root.cursorIndex === root.removeServerCursorIndex && serverRow.editing
                    tooltipText: "Stop polling this server and forget its settings"
                    foreground: root.urgent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    iconSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(5)

                    onHovered: function (hovered) {
                        if (hovered && serverRow.editing)
                            root.setCursor(root.removeServerCursorIndex);
                    }
                    onClicked: root.removeServer(serverRow.rowIndex)
                }
            }
        }
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

                // In a merged list the severity alone does not say where to
                // go and fix it, so the server travels with the row.
                Text {
                    visible: root.multiServer && text !== ""
                    text: problemRow.problem ? String(problemRow.problem.serverName || "") : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: Style.space(140)
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
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
