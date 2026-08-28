import QtQuick
import QtQml.Models
import Quickshell
import "Model.js" as Model

// The pool of per-server Services and the aggregation over them. It exposes
// the same property names a single Service did, so the panel's bindings read
// one merged Zabbix rather than N.
Item {
    id: root

    property var settings: ({})
    readonly property string home: Quickshell.env("HOME") || ""

    // Both lists are only reassigned when their content actually changes.
    // Rebinding them on every filter toggle would tear the Services down and
    // refetch, and the id list is the Instantiator model precisely so that
    // editing a server's URL updates one delegate instead of rebuilding all.
    property var servers: []
    property var serverIdList: []
    property var serverStates: []
    property bool recomputePending: false

    readonly property var globals: Model.normalizeSettings(settings, home)
    readonly property var selectedServerIds: Model.parseServerSelection(settings ? settings.selectedServers : [], servers)
    readonly property var aggregate: Model.aggregateServerStates(serverStates, selectedServerIds)
    readonly property var problems: Model.mergeServerProblems(serverStates, selectedServerIds)

    readonly property int serverCount: servers.length
    readonly property bool multiServer: servers.length > 1
    readonly property int connectedCount: aggregate.connectedCount
    readonly property int failingCount: aggregate.failingCount
    readonly property bool partial: aggregate.partial

    // Derived from settings rather than from poll state, so the panel knows a
    // server exists before the first snapshot lands.
    readonly property bool configured: {
        for (var i = 0; i < servers.length; i++)
            if (servers[i].configured === true)
                return true;
        return false;
    }
    readonly property bool hasData: aggregate.hasData
    readonly property bool loading: aggregate.loading
    readonly property bool stale: aggregate.stale
    readonly property bool truncated: aggregate.truncated
    readonly property bool insecureTls: aggregate.insecureTls
    readonly property double lastUpdatedMs: aggregate.lastUpdatedMs
    readonly property string serverVersion: aggregate.serverVersion
    readonly property string connectionState: aggregate.connectionState
    readonly property string lastError: aggregate.lastError
    readonly property string errorCategory: aggregate.errorCategory
    readonly property string identityError: aggregate.identityError

    // Filters are global across servers, so they are read once here.
    readonly property var selectedSeverities: globals.severities
    readonly property string acknowledgement: globals.acknowledgement
    readonly property bool acknowledgedByMeSetting: globals.acknowledgedByMe
    readonly property bool acknowledgedByMe: globals.acknowledgedByMeActive
    readonly property bool showSuppressed: globals.showSuppressed
    readonly property bool showSymptoms: globals.showSymptoms
    readonly property bool showUnmonitored: globals.showUnmonitored
    readonly property int refreshIntervalSec: globals.refreshIntervalSec

    function syncServers() {
        var next = Model.normalizeServers(settings, home);
        if (JSON.stringify(next) !== JSON.stringify(servers))
            servers = next;
        var ids = Model.serverIds(servers);
        if (JSON.stringify(ids) !== JSON.stringify(serverIdList))
            serverIdList = ids;
    }

    function serverFor(id) {
        for (var i = 0; i < servers.length; i++)
            if (servers[i].id === id)
                return servers[i];
        return null;
    }

    function stateFor(id) {
        for (var i = 0; i < serverStates.length; i++)
            if (serverStates[i].id === id)
                return serverStates[i];
        return null;
    }

    // Every Service change lands here; a whole refresh emits many, so the walk
    // is coalesced to one pass per event loop turn.
    function schedule() {
        if (recomputePending)
            return;
        recomputePending = true;
        Qt.callLater(recompute);
    }

    function recompute() {
        recomputePending = false;
        var output = [];
        for (var i = 0; i < pool.count; i++) {
            var service = pool.objectAt(i);
            if (service)
                output.push(service.snapshot());
        }
        serverStates = output;
    }

    function refresh(force) {
        for (var i = 0; i < pool.count; i++) {
            var service = pool.objectAt(i);
            if (service)
                service.refresh(force);
        }
    }

    onSettingsChanged: syncServers()
    Component.onCompleted: syncServers()

    Instantiator {
        id: pool
        model: root.serverIdList

        delegate: Service {
            required property var modelData
            settings: root.settings
            server: root.serverFor(modelData)
            onChanged: root.schedule()
        }

        onObjectAdded: root.schedule()
        onObjectRemoved: root.schedule()
    }
}
