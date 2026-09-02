import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Shared.js" as Shared

// One service exists per monitor-local widget. Shared.js coordinates claims
// and publication so only one instance polls for each effective configuration.
Item {
    id: root

    property var settings: ({})
    // The connection quartet this instance polls. Null falls back to the
    // top-level settings keys, which is how a pre-servers configuration works.
    property var server: null
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property var normalized: Model.normalizeSettings(settings, home, server)
    readonly property string serverId: server ? String(server.id || "") : ""
    readonly property string serverLabel: server ? String(server.label || server.name || "") : ""
    readonly property string tokenFilePath: normalized.tokenFile
    readonly property bool insecureTls: normalized.insecureTls
    readonly property var selectedSeverities: normalized.severities
    readonly property string acknowledgement: normalized.acknowledgement
    // The raw checkbox state, kept distinct from the effective filter so the
    // panel can show it ticked while the acknowledgement state renders it inert.
    readonly property bool acknowledgedByMeSetting: normalized.acknowledgedByMe
    readonly property bool acknowledgedByMe: normalized.acknowledgedByMeActive
    readonly property bool showSuppressed: normalized.showSuppressed
    readonly property bool showSymptoms: normalized.showSymptoms
    readonly property bool showUnmonitored: normalized.showUnmonitored
    readonly property bool configured: normalized.endpoint !== "" && tokenFilePath !== ""
    readonly property bool hasData: lastUpdatedMs > 0
    readonly property string signature: Model.configurationSignature(settings, token, home, server)
    readonly property string authorizationSignature: Model.dataSourceSignature(settings, token, home, server)
    readonly property int effectiveIntervalMs: Model.failureBackoffMs(normalized.refreshIntervalSec, failureStreak)

    property string token: ""
    property string joinedSignature: ""
    property string joinedAuthorizationSignature: ""
    property string validatedSignature: ""
    property string connectionState: "unconfigured"
    property bool loading: false
    property bool stale: false
    property string lastError: ""
    property string errorCategory: ""
    property string serverVersion: ""
    property string identityUserId: ""
    property string identityUserSignature: ""
    property string identityError: ""
    property double lastUpdatedMs: 0
    property var problems: []
    property bool truncated: false
    property int failureStreak: 0

    property var transaction: null
    property var censusRows: null
    property var rankResult: null
    property string requestPhase: ""
    property int requestGeneration: 0
    property int activeGeneration: 0
    property int activeClaimId: 0
    property var sharedBasePayload: null
    property string requestOutput: ""
    property string requestError: ""

    // QML bindings cannot track an Instantiator's children, so the pool that
    // aggregates several servers recomputes on this instead.
    signal changed

    onProblemsChanged: changed()
    onLoadingChanged: changed()
    onStaleChanged: changed()
    onTruncatedChanged: changed()
    onLastErrorChanged: changed()
    onErrorCategoryChanged: changed()
    onConnectionStateChanged: changed()
    onServerVersionChanged: changed()
    onLastUpdatedMsChanged: changed()
    onIdentityErrorChanged: changed()
    onConfiguredChanged: changed()

    function snapshot() {
        return {
            id: serverId,
            label: serverLabel,
            endpointError: normalized.endpointError,
            configured: configured,
            hasData: hasData,
            loading: loading,
            stale: stale,
            truncated: truncated,
            lastError: lastError,
            errorCategory: errorCategory,
            connectionState: connectionState,
            serverVersion: serverVersion,
            lastUpdatedMs: lastUpdatedMs,
            insecureTls: insecureTls,
            identityError: identityError,
            acknowledgedByMe: acknowledgedByMe,
            problems: problems
        };
    }

    function syncMembership() {
        var authorizationChanged = joinedAuthorizationSignature !== "" && joinedAuthorizationSignature !== authorizationSignature;
        if (!configured || token === "") {
            if (joinedSignature !== "")
                Shared.leave(joinedSignature, root);
            if (authorizationChanged)
                resetPublished();
            joinedSignature = "";
            joinedAuthorizationSignature = "";
            sharedBasePayload = null;
            return;
        }
        if (joinedSignature === signature)
            return;

        var carry = authorizationChanged ? null : currentPayload();
        if (carry) {
            carry.problems = Model.filterProblems(carry.problems, selectedSeverities, acknowledgement);
            carry.stale = true;
        }
        if (joinedSignature !== "")
            Shared.leave(joinedSignature, root);
        if (authorizationChanged)
            resetPublished();
        joinedSignature = signature;
        joinedAuthorizationSignature = authorizationSignature;
        var shared = Shared.join(joinedSignature, root);
        sharedBasePayload = shared || carry;
        if (shared)
            applyShared(shared);
    }

    function forgetIdentity() {
        identityUserId = "";
        identityUserSignature = "";
        identityError = "";
    }

    function resetPublished() {
        forgetIdentity();
        problems = [];
        truncated = false;
        serverVersion = "";
        lastUpdatedMs = 0;
        stale = false;
        lastError = "";
        errorCategory = "";
        failureStreak = 0;
        connectionState = "unconfigured";
    }

    function currentPayload() {
        if (!hasData)
            return null;
        return {
            problems: problems,
            truncated: truncated,
            serverVersion: serverVersion,
            lastUpdatedMs: lastUpdatedMs,
            stale: stale,
            lastError: lastError,
            errorCategory: errorCategory,
            connectionState: connectionState,
            failureStreak: failureStreak,
            insecureTls: insecureTls,
            identityError: identityError
        };
    }

    function copyPayload(payload) {
        if (!payload)
            return null;
        return {
            problems: (payload.problems || []).slice(),
            truncated: payload.truncated === true,
            serverVersion: String(payload.serverVersion || ""),
            lastUpdatedMs: Number(payload.lastUpdatedMs || 0),
            stale: payload.stale === true,
            lastError: String(payload.lastError || ""),
            errorCategory: String(payload.errorCategory || ""),
            connectionState: String(payload.connectionState || ""),
            failureStreak: Number(payload.failureStreak || 0),
            insecureTls: payload.insecureTls === true,
            identityError: String(payload.identityError || "")
        };
    }

    function applyShared(payload) {
        if (!payload)
            return;
        problems = payload.problems || [];
        truncated = payload.truncated === true;
        serverVersion = String(payload.serverVersion || "");
        lastUpdatedMs = Number(payload.lastUpdatedMs || 0);
        stale = payload.stale === true;
        lastError = String(payload.lastError || "");
        errorCategory = String(payload.errorCategory || "");
        connectionState = String(payload.connectionState || (lastUpdatedMs > 0 ? "connected" : "error"));
        failureStreak = Number(payload.failureStreak || 0);
        identityError = String(payload.identityError || "");
        loading = false;
    }

    function applySharedLoading() {
        loading = true;
        lastError = "";
        errorCategory = "";
        if (!hasData)
            connectionState = "connecting";
    }

    function applySharedAbandoned() {
        if (activeClaimId === 0)
            loading = false;
    }

    function adoptShared(signatureValue) {
        var current = Shared.snapshot(signatureValue);
        if (current)
            applyShared(current);
        else
            loading = false;
        if (Shared.isClaimed(signatureValue, Date.now()))
            applySharedLoading();
    }

    function configurationError() {
        if (normalized.endpointError !== "")
            return {
                category: "endpoint",
                message: normalized.endpointError
            };
        if (tokenFilePath === "")
            return {
                category: "token-file",
                message: "API token file is not configured"
            };
        if (token === "")
            return {
                category: "token-file",
                message: "API token file is missing, unreadable, or empty"
            };
        return null;
    }

    function refresh(force) {
        if (loading) {
            if (activeClaimId > 0)
                return false;
            if (joinedSignature !== "" && Shared.isClaimed(joinedSignature, Date.now()))
                return false;
            loading = false;
        }
        syncMembership();
        var setupError = configurationError();
        if (setupError) {
            connectionState = normalized.endpoint === "" ? "unconfigured" : "error";
            lastError = setupError.message;
            errorCategory = setupError.category;
            stale = hasData;
            return false;
        }

        var now = Date.now();
        if (!Shared.claim(signature, now, force === true, normalized.refreshIntervalSec * 1000, root)) {
            adoptShared(signature);
            return false;
        }

        activeClaimId = Shared.currentClaim(signature);
        transaction = Model.beginTransaction(sharedBasePayload);
        censusRows = null;
        rankResult = null;
        if (force === true)
            identityError = "";
        loading = true;
        stale = hasData && stale;
        lastError = "";
        errorCategory = "";
        if (validatedSignature === signature && serverVersion !== "")
            startNextDataRequest();
        else
            startVersionRequest();
        return true;
    }

    // The token's own user id is only needed for the "acknowledged by me"
    // filter, so it is resolved lazily and cached per endpoint+token. A failed
    // resolution is remembered too; a forced refresh clears it and retries.
    function identityRequired() {
        if (!acknowledgedByMe)
            return false;
        if (identityUserSignature === authorizationSignature && identityUserId !== "")
            return false;
        return identityError === "";
    }

    function resolvedUserId() {
        return identityUserSignature === authorizationSignature ? identityUserId : "";
    }

    function startNextDataRequest() {
        if (identityRequired())
            startIdentityRequest();
        else
            startCensusRequest();
    }

    // Every phase hand-off waits a tick and re-checks that this refresh is still
    // the current, owned one before continuing.
    function continueWhenCurrent(step) {
        var generation = activeGeneration;
        var currentSignature = signature;
        Qt.callLater(function () {
            if (root.loading && root.activeGeneration === generation && root.signature === currentSignature && root.activeClaimId > 0)
                step();
        });
    }

    function startVersionRequest() {
        connectionState = "check_version";
        startRequest("version", Model.buildApiInfoVersionRequest(1), false);
    }

    function startIdentityRequest() {
        connectionState = "identify_user";
        var identityRequest;
        try {
            identityRequest = Model.buildUserCheckAuthenticationRequest(token, 4);
        } catch (exception) {
            identityError = Model.safeMessage(exception.message, [token]);
            startCensusRequest();
            return;
        }
        startRequest("identity", identityRequest, false);
    }

    // A refresh ranks before it fetches: census the matching problems cheaply,
    // up to the census cap, ask trigger.get which of them are still live, then
    // pull full detail for the survivors that fit the limit.
    function startCensusRequest() {
        connectionState = "fetch_problems";
        startRequest("census", Model.buildProblemCensusRequest({
            severities: selectedSeverities,
            acknowledgement: acknowledgement,
            acknowledgedByUserId: acknowledgedByMe ? resolvedUserId() : "",
            showSuppressed: normalized.showSuppressed,
            showSymptoms: normalized.showSymptoms
        }, 2), true);
    }

    function startTriggersRequest() {
        connectionState = "enrich_hosts";
        startRequest("triggers", Model.buildTriggerGetRequest({
            triggerIds: censusRows,
            showUnmonitored: normalized.showUnmonitored
        }, 3), true);
    }

    function startDetailRequest() {
        connectionState = "fetch_problems";
        startRequest("detail", Model.buildProblemDetailRequest(rankResult.eventIds, 5), true);
    }

    function finishWithoutProblems() {
        Model.stageProblems(transaction, {
            problems: [],
            truncated: false
        });
        finishSuccess();
    }

    function startRequest(phase, rpcRequest, authenticated) {
        if (requestProcess.running) {
            failRefresh({
                category: "transport",
                message: "A Zabbix request is already running"
            });
            return;
        }
        requestPhase = phase;
        requestOutput = "";
        requestError = "";
        requestGeneration += 1;
        activeGeneration = requestGeneration;
        requestProcess.runningGeneration = activeGeneration;
        try {
            requestProcess.environment = Model.buildCurlEnvironment(normalized.endpoint, Model.requestBody(rpcRequest), token, {
                authenticated: authenticated,
                caCertificateFile: normalized.caCertificateFile,
                insecureTls: normalized.insecureTls,
                connectTimeoutSec: Model.DEFAULT_CONNECT_TIMEOUT_SEC,
                totalTimeoutSec: Model.DEFAULT_TOTAL_TIMEOUT_SEC
            });
        } catch (exception) {
            failRefresh({
                category: "endpoint",
                message: Model.safeMessage(exception.message, [token])
            });
            return;
        }
        requestProcess.running = true;
        watchdog.restart();
    }

    function completeRequest(exitCode, generation) {
        watchdog.stop();
        if (generation !== activeGeneration) {
            return;
        }

        var transport = Model.classifyCurlResult(exitCode, String(requestStdout.text || requestOutput || ""), String(requestStderr.text || requestError || ""), [token]);
        if (!transport.ok) {
            failRefresh(transport);
            return;
        }

        if (requestPhase === "version") {
            var versionResult = Model.parseVersionResponse(transport.body, 1);
            if (!versionResult.ok) {
                failRefresh(versionResult);
                return;
            }
            serverVersion = versionResult.result;
            validatedSignature = signature;
            continueWhenCurrent(function () {
                root.startNextDataRequest();
            });
            return;
        }

        if (requestPhase === "identity") {
            var identityResult = Model.parseIdentityResponse(transport.body, 4, [token]);
            if (identityResult.ok) {
                identityUserId = identityResult.userId;
                identityUserSignature = authorizationSignature;
                identityError = "";
            } else {
                // Losing the identity only costs the "by me" narrowing, so the
                // refresh continues and the panel explains the wider result.
                identityUserId = "";
                identityUserSignature = "";
                identityError = identityResult.message || "Zabbix did not identify the API token's user";
            }
            continueWhenCurrent(function () {
                root.startCensusRequest();
            });
            return;
        }

        if (requestPhase === "census") {
            var censusResponse = Model.parseJsonRpcResponse(transport.body, 2, "problem.get", [token]);
            if (!censusResponse.ok) {
                failRefresh(censusResponse);
                return;
            }
            if (!(censusResponse.result instanceof Array)) {
                failRefresh({
                    category: "malformed-response",
                    message: "Zabbix problem.get returned an invalid result"
                });
                return;
            }
            censusRows = Model.normalizeCensus(censusResponse.result);
            if (censusRows.length === 0) {
                Model.stageHosts(transaction, {});
                finishWithoutProblems();
                return;
            }
            continueWhenCurrent(function () {
                root.startTriggersRequest();
            });
            return;
        }

        if (requestPhase === "triggers") {
            var triggerResponse = Model.parseJsonRpcResponse(transport.body, 3, "trigger.get", [token]);
            if (!triggerResponse.ok) {
                failRefresh(triggerResponse);
                return;
            }
            if (!(triggerResponse.result instanceof Array)) {
                failRefresh({
                    category: "malformed-response",
                    message: "Zabbix trigger.get returned an invalid result"
                });
                return;
            }
            var hostMap = Model.normalizeHosts(triggerResponse.result);
            Model.stageHosts(transaction, hostMap);
            rankResult = Model.rankCensus(censusRows, hostMap, {
                problemLimit: normalized.problemLimit,
                showUnmonitored: normalized.showUnmonitored
            });
            if (rankResult.eventIds.length === 0) {
                finishWithoutProblems();
                return;
            }
            continueWhenCurrent(function () {
                root.startDetailRequest();
            });
            return;
        }

        if (requestPhase === "detail") {
            var detailResponse = Model.parseJsonRpcResponse(transport.body, 5, "problem.get", [token]);
            if (!detailResponse.ok) {
                failRefresh(detailResponse);
                return;
            }
            if (!(detailResponse.result instanceof Array)) {
                failRefresh({
                    category: "malformed-response",
                    message: "Zabbix problem.get returned an invalid result"
                });
                return;
            }
            var detail = Model.normalizeProblemResult(detailResponse.result, normalized.problemLimit);
            // Truncation is a property of the ranking, not of this response:
            // detail only ever asks for what already fits the limit.
            detail.truncated = rankResult.truncated;
            Model.stageProblems(transaction, detail);
            finishSuccess();
            return;
        }
    }

    function finishSuccess() {
        var now = Date.now();
        var result = Model.commitTransaction(transaction, {
            version: serverVersion,
            publishedMs: now
        });
        if (!result.ok) {
            failRefresh({
                category: "malformed-response",
                message: result.error
            });
            return;
        }
        var payload = result.published;
        payload.serverVersion = serverVersion;
        payload.lastUpdatedMs = now;
        payload.stale = false;
        payload.lastError = "";
        payload.errorCategory = "";
        payload.connectionState = insecureTls ? "insecure" : "connected";
        payload.failureStreak = 0;
        payload.insecureTls = insecureTls;
        payload.identityError = identityError;
        transaction = null;
        censusRows = null;
        rankResult = null;
        var claim = activeClaimId;
        activeClaimId = 0;
        if (Shared.publish(signature, payload, now, root, claim)) {
            sharedBasePayload = payload;
            applyShared(payload);
        } else {
            adoptShared(signature);
        }
    }

    function failRefresh(error) {
        watchdog.stop();
        var category = String(error && error.category || "transport");
        var message = Model.safeMessage(error && error.message || "Zabbix request failed", [token]);
        var nextFailureStreak = Math.min(30, failureStreak + 1);
        var base = transaction ? transaction.published : sharedBasePayload;
        transaction = null;
        censusRows = null;
        rankResult = null;

        if (joinedSignature !== "" && activeClaimId > 0) {
            var payload = copyPayload(base) || {
                problems: [],
                truncated: false,
                serverVersion: serverVersion,
                lastUpdatedMs: 0,
                stale: false,
                lastError: lastError,
                errorCategory: errorCategory,
                connectionState: connectionState,
                failureStreak: nextFailureStreak,
                insecureTls: insecureTls,
                identityError: identityError
            };
            payload.stale = payload.lastUpdatedMs > 0;
            payload.identityError = identityError;
            payload.lastError = message;
            payload.errorCategory = category;
            payload.connectionState = "error";
            payload.failureStreak = nextFailureStreak;
            var claim = activeClaimId;
            activeClaimId = 0;
            if (!Shared.publish(joinedSignature, payload, Date.now(), root, claim)) {
                adoptShared(joinedSignature);
                return;
            }
            sharedBasePayload = payload;
        }

        failureStreak = nextFailureStreak;
        loading = false;
        stale = hasData;
        connectionState = "error";
        lastError = message;
        errorCategory = category;
    }

    function cancelRequest() {
        watchdog.stop();
        if (joinedSignature !== "" && activeClaimId > 0)
            Shared.abandon(joinedSignature, root, activeClaimId);
        activeClaimId = 0;
        transaction = null;
        censusRows = null;
        rankResult = null;
        loading = false;
        requestGeneration += 1;
        activeGeneration = requestGeneration;
        if (requestProcess.running) {
            requestProcess.running = false;
        }
    }

    function scheduleConfigurationReload() {
        cancelRequest();
        validatedSignature = "";
        syncMembership();
        reloadTimer.restart();
    }

    onSettingsChanged: scheduleConfigurationReload()
    onServerChanged: scheduleConfigurationReload()
    onTokenChanged: scheduleConfigurationReload()

    Component.onCompleted: reloadTimer.restart()
    Component.onDestruction: {
        cancelRequest();
        if (joinedSignature !== "")
            Shared.leave(joinedSignature, root);
    }

    FileView {
        id: tokenFile
        path: root.tokenFilePath
        watchChanges: true
        printErrors: false
        onLoaded: root.token = Model.firstNonEmptyLine(text())
        onFileChanged: reload()
        onLoadFailed: {
            root.token = "";
            tokenRetry.restart();
        }
    }

    Process {
        id: requestProcess
        property int runningGeneration: 0
        running: false
        command: Model.curlArgv()
        stdout: StdioCollector {
            id: requestStdout
            waitForEnd: true
            onStreamFinished: root.requestOutput = text
        }
        stderr: StdioCollector {
            id: requestStderr
            waitForEnd: true
            onStreamFinished: root.requestError = text
        }
        onExited: function (exitCode, exitStatus) {
            root.completeRequest(exitCode, runningGeneration);
        }
    }

    Timer {
        id: watchdog
        interval: (Model.DEFAULT_TOTAL_TIMEOUT_SEC + 8) * 1000
        repeat: false
        onTriggered: {
            if (!requestProcess.running)
                return;
            root.requestGeneration += 1;
            root.activeGeneration = root.requestGeneration;
            requestProcess.running = false;
            root.failRefresh({
                category: "timeout",
                message: "Zabbix request timed out"
            });
        }
    }

    Timer {
        id: tokenRetry
        interval: 5000
        repeat: false
        onTriggered: tokenFile.reload()
    }

    Timer {
        id: reloadTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (requestProcess.running) {
                restart();
                return;
            }
            root.syncMembership();
            root.refresh(false);
        }
    }

    Timer {
        interval: root.effectiveIntervalMs
        repeat: true
        running: true
        onTriggered: root.refresh(false)
    }
}
