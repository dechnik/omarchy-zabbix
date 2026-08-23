// node test/model.test.js
var assert = require("assert")
var fs = require("fs")
var path = require("path")
var Model = require("../Model.js")

function loadShared() {
  var source = fs.readFileSync(path.join(__dirname, "..", "Shared.js"), "utf8")
    .replace(/^\.pragma .*$/m, "")
    .replace(/^\.import .*$/m, "")
  var exports = "; module.exports = { group: group, join: join, leave: leave, claim: claim, currentClaim: currentClaim, abandon: abandon, publish: publish, snapshot: snapshot, memberCount: memberCount, isClaimed: isClaimed, resetForTests: resetForTests }"
  var box = { exports: {} }
  new Function("Model", "module", source + exports)(Model, box)
  return box.exports
}

// Configuration and token handling.
assert.strictEqual(Model.normalizeEndpoint(" https://monitor.test/zabbix/ "), "https://monitor.test/zabbix/api_jsonrpc.php")
assert.strictEqual(Model.normalizeEndpoint("https://monitor.test/api_jsonrpc.php"), "https://monitor.test/api_jsonrpc.php")
assert.strictEqual(Model.normalizeEndpoint("http://monitor.test/zabbix"), "")
assert.strictEqual(Model.endpointError("http://monitor.test"), "Zabbix URL must use HTTPS")
assert.strictEqual(Model.normalizeEndpoint("https://user:pass@monitor.test"), "")
assert.strictEqual(Model.expandHome("~/.config/x", "/home/test"), "/home/test/.config/x")
assert.strictEqual(Model.expandHome("~", "/home/test/"), "/home/test")
assert.strictEqual(Model.expandHome("/etc/x", "/home/test"), "/etc/x")
assert.strictEqual(Model.firstNonEmptyLine("\n \r\n token-value \nsecond"), "token-value")
assert.strictEqual(Model.firstNonEmptyLine("\n \t"), "")

var normalized = Model.normalizeSettings({
  url: "https://z.example/zabbix/",
  refreshIntervalSec: 1,
  problemLimit: 99999,
  tokenFile: "~/token",
  caCertificateFile: "~/ca.pem",
  insecureTls: "true",
  severities: "5,2,2,bad,-1"
}, "/home/u")
assert.strictEqual(normalized.endpoint, "https://z.example/zabbix/api_jsonrpc.php")
assert.strictEqual(normalized.refreshIntervalSec, Model.MIN_REFRESH_INTERVAL_SEC)
assert.strictEqual(normalized.problemLimit, Model.MAX_PROBLEM_LIMIT)
assert.strictEqual(normalized.tokenFile, "/home/u/token")
assert.strictEqual(normalized.caCertificateFile, "/home/u/ca.pem")
assert.strictEqual(normalized.insecureTls, true)
assert.deepStrictEqual(normalized.severities, [2, 5])

assert.strictEqual(Model.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
assert.strictEqual(Model.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
assert.strictEqual(Model.sha256("Zażółć"), "1b45560b47f44bbf87bf66cb5d1840e833c5857f8c5656a2f42656153853f8d1")
var signature = Model.configurationSignature({ url: "https://z.example", severities: "5,4" }, "super-secret", "/home/u")
assert.strictEqual(signature.length, 64)
assert.strictEqual(signature.indexOf("super-secret"), -1)
assert.strictEqual(signature, Model.configurationSignature({ url: "https://z.example/", severities: [4, 5] }, "super-secret", "/home/u"))
assert.notStrictEqual(signature, Model.configurationSignature({ url: "https://z.example", severities: "4,5" }, "rotated", "/home/u"))
assert.strictEqual(
  Model.dataSourceSignature({ url: "https://z.example", severities: [5] }, "super-secret", "/home/u"),
  Model.dataSourceSignature({ url: "https://z.example", severities: [1, 2] }, "super-secret", "/home/u"))
assert.notStrictEqual(
  Model.dataSourceSignature({ url: "https://z.example" }, "super-secret", "/home/u"),
  Model.dataSourceSignature({ url: "https://z.example" }, "rotated", "/home/u"))

// Version comparison.
assert.deepStrictEqual(Model.parseVersion("7.0.12"), { raw: "7.0.12", major: 7, minor: 0, patch: 12 })
assert.strictEqual(Model.compareVersions("7.0", "7.0.0"), 0)
assert.strictEqual(Model.compareVersions("7.2.1", "7.0.99"), 1)
assert.strictEqual(Model.compareVersions("6.4.20", "7.0"), -1)
assert.strictEqual(Model.compareVersions("bad", "7.0"), null)
assert.strictEqual(Model.isSupportedVersion("7.0.0rc1"), true)
assert.strictEqual(Model.isSupportedVersion("6.4.20"), false)
assert.strictEqual(Model.isSupportedVersion("7"), false)

// Fixed transport, strict config escaping, and status parsing.
assert.strictEqual(Model.curlConfigEscape('a\\b"c'), 'a\\\\b\\"c')
assert.throws(function() { Model.curlConfigEscape("safe\ninsecure") }, /line breaks/)
assert.deepStrictEqual(Model.curlArgv().slice(0, 2), ["bash", "-c"])
assert.strictEqual(Model.curlArgv().length, 3)
assert.ok(Model.FETCH_SCRIPT.indexOf("--config -") >= 0)
assert.ok(Model.FETCH_SCRIPT.indexOf("Authorization: Bearer") >= 0)
assert.ok(Model.FETCH_SCRIPT.indexOf("--insecure") < 0, "TLS mode is a controlled curl-config directive")

var versionEnvironment = Model.buildCurlEnvironment(
  "https://z.example", JSON.stringify(Model.buildApiInfoVersionRequest()), "must-not-be-used",
  { authenticated: false })
assert.strictEqual(versionEnvironment.ZABBIX_AUTH, "0")
assert.strictEqual(versionEnvironment.ZABBIX_TOKEN, "")
var authEnvironment = Model.buildCurlEnvironment(
  "https://z.example", "{}", "tok\"en", { authenticated: true, caCertificateFile: "/tmp/ca.pem", insecureTls: true })
assert.strictEqual(authEnvironment.ZABBIX_TOKEN, "tok\\\"en")
assert.strictEqual(authEnvironment.ZABBIX_CA_FILE, "/tmp/ca.pem")
assert.strictEqual(authEnvironment.ZABBIX_INSECURE, "1")
assert.strictEqual(Model.curlArgv().join(" ").indexOf("tok\"en"), -1)
assert.throws(function() {
  Model.buildCurlEnvironment("https://z.example\nheader = x", "{}", "token", { authenticated: true })
}, /invalid|HTTPS/)
assert.throws(function() {
  Model.buildCurlEnvironment("https://z.example", "{}\ninsecure", "token", { authenticated: true })
}, /line breaks/)

assert.deepStrictEqual(Model.parseCurlOutput('{"ok":1}\n' + Model.CURL_STATUS_MARKER + "200"), {
  ok: true, body: '{"ok":1}', status: 200, error: ""
})
assert.strictEqual(Model.parseCurlOutput("body").ok, false)
assert.strictEqual(Model.classifyCurlResult(0, "{}\n" + Model.CURL_STATUS_MARKER + "200", "").ok, true)
assert.strictEqual(Model.classifyCurlResult(22, "denied\n" + Model.CURL_STATUS_MARKER + "401", "").category, "authentication")
assert.strictEqual(Model.classifyCurlResult(28, "", "").category, "timeout")
assert.strictEqual(Model.classifyCurlResult(60, "", "").category, "tls")
assert.strictEqual(Model.classifyCurlResult(6, "", "").category, "network")
assert.strictEqual(Model.classifyCurlResult(3, "", "").category, "endpoint")
assert.strictEqual(Model.classifyCurlResult(127, "", "").category, "transport")
assert.strictEqual(Model.classifyCurlResult(0, "redirect\n" + Model.CURL_STATUS_MARKER + "302", "").category, "endpoint")
assert.strictEqual(Model.classifyCurlResult(0, "server\n" + Model.CURL_STATUS_MARKER + "500", "").category, "http")

// Exact JSON-RPC request shapes.
assert.deepStrictEqual(Model.buildApiInfoVersionRequest(), {
  jsonrpc: "2.0", method: "apiinfo.version", params: {}, id: 1
})
assert.deepStrictEqual(Model.buildProblemGetRequest([5, 4, 5], 100), {
  jsonrpc: "2.0",
  method: "problem.get",
  params: {
    output: ["eventid", "objectid", "clock", "name", "severity", "acknowledged", "suppressed", "cause_eventid"],
    selectTags: ["tag", "value"],
    source: 0,
    object: 0,
    recent: false,
    severities: [4, 5],
    sortfield: ["eventid"],
    sortorder: "DESC",
    limit: 101
  },
  id: 2
})
assert.deepStrictEqual(Model.buildTriggerGetRequest(["8", "7", "8", "bad"]), {
  jsonrpc: "2.0",
  method: "trigger.get",
  params: { output: ["triggerid"], triggerids: ["8", "7"], selectHosts: ["hostid", "name"] },
  id: 3
})

// JSON-RPC parsing and safe classification.
assert.deepStrictEqual(Model.parseJsonRpcResponse('{"jsonrpc":"2.0","result":[],"id":2}', 2, "problem.get").result, [])
assert.strictEqual(Model.parseJsonRpcResponse("<html>", 2).category, "malformed-response")
assert.strictEqual(Model.parseJsonRpcResponse('{"jsonrpc":"2.0","result":[],"id":9}', 2).category, "malformed-response")
var denied = Model.parseJsonRpcResponse(JSON.stringify({
  jsonrpc: "2.0", id: 2, error: { code: -32602, message: "Invalid params.", data: "No permissions to call problem.get" }
}), 2, "problem.get")
assert.strictEqual(denied.category, "permission")
assert.ok(denied.message.indexOf("problem.get") >= 0)
var rejected = Model.parseJsonRpcResponse(JSON.stringify({
  jsonrpc: "2.0", id: 2, error: { code: -32602, message: "Not authorized", data: "super-secret" }
}), 2, "problem.get", ["super-secret"])
assert.strictEqual(rejected.category, "authentication")
assert.strictEqual(rejected.message.indexOf("super-secret"), -1)
assert.strictEqual(Model.parseVersionResponse('{"jsonrpc":"2.0","result":"7.0.2","id":1}').ok, true)
assert.strictEqual(Model.parseVersionResponse('{"jsonrpc":"2.0","result":"6.4.1","id":1}').category, "version")
assert.strictEqual(Model.parseVersionResponse('{"jsonrpc":"2.0","result":"unknown","id":1}').category, "malformed-response")
assert.strictEqual(Model.classifyJsonRpcError({ code: -32500, data: "API token expired." }, "problem.get").category, "authentication")
assert.strictEqual(Model.classifyJsonRpcError({ code: -32500, data: 'No permissions to call "trigger.get".' }, "trigger.get").category, "permission")

// Problems, truncation, host enrichment, filtering, and sorting.
function row(eventId, triggerId, severity, clock) {
  return {
    eventid: eventId,
    objectid: triggerId,
    clock: String(clock),
    name: "Problem " + eventId,
    severity: String(severity),
    acknowledged: eventId === "2" ? "1" : "0",
    suppressed: eventId === "3" ? "1" : "0",
    cause_eventid: eventId === "3" ? "1" : "0",
    tags: [{ tag: "service", value: "web" }, null, { tag: "", value: "" }]
  }
}

var normalizedResult = Model.normalizeProblemResult([
  row("1", "10", 4, 100),
  { eventid: "bad", objectid: "10", severity: "9" },
  row("2", "20", 5, 300),
  row("3", "30", 5, 200)
], 3)
assert.strictEqual(normalizedResult.truncated, true)
assert.strictEqual(normalizedResult.problems.length, 3)
assert.strictEqual(normalizedResult.problems[1].acknowledged, true)
assert.strictEqual(normalizedResult.problems[2].suppressed, true)
assert.strictEqual(normalizedResult.problems[2].isSymptom, true)
assert.deepStrictEqual(normalizedResult.problems[0].tags, [{ tag: "service", value: "web" }])
assert.strictEqual(Model.normalizeProblem({ eventid: "", objectid: "1", severity: 1 }), null)

var hostMap = Model.normalizeHosts([
  { triggerid: "10", hosts: [{ hostid: "100", name: "web-1" }] },
  { triggerid: "20", hosts: [{ hostid: "200", name: "db-1" }, { hostid: "201", name: "db-2" }] }
])
var joined = Model.joinProblemHosts(normalizedResult.problems, hostMap)
assert.deepStrictEqual(joined[0].hostNames, ["web-1"])
assert.deepStrictEqual(joined[1].hostNames, ["db-1", "db-2"])
assert.strictEqual(joined[2].hostsAvailable, false)
assert.strictEqual(joined[2].hostLabel, "Host unavailable")
assert.strictEqual(joined.length, 3, "missing host enrichment must retain the problem")
assert.deepStrictEqual(Model.buildTriggerGetRequest([]).params.triggerids, [])

assert.deepStrictEqual(Model.parseSeveritySelection("5,2,5,nope"), [2, 5])
assert.deepStrictEqual(Model.parseSeveritySelection([]), [0, 1, 2, 3, 4, 5])
assert.strictEqual(Model.persistSeveritySelection([5, 1]), "1,5")
assert.deepStrictEqual(Model.toggleSeverity([5], 5), [5], "the final severity cannot be removed")
assert.deepStrictEqual(Model.toggleSeverity([4, 5], 4), [5])
assert.strictEqual(Model.SEVERITIES.length, 6)
assert.deepStrictEqual(Model.SEVERITIES[5], { value: 5, label: "Disaster", color: "#E45959" })
assert.deepStrictEqual(Model.filterProblems(joined, [5]).map(function(p) { return p.eventId }), ["2", "3"])
assert.deepStrictEqual(Model.sortProblems(joined).map(function(p) { return p.eventId }), ["2", "3", "1"])
var summary = Model.highestSeveritySummary(joined, [0, 1, 2, 3, 4, 5], { available: true, truncated: true })
assert.strictEqual(summary.severity, 5)
assert.strictEqual(summary.count, 2)
assert.strictEqual(summary.color, "#E45959")
assert.strictEqual(summary.truncated, true)
assert.deepStrictEqual(Model.highestSeveritySummary([], [5]), {
  available: true, count: 0, severity: null, definition: null, color: "", truncated: false
})
assert.strictEqual(Model.highestSeveritySummary(joined, [5], { available: false }).available, false)
assert.strictEqual(Model.severitySummary(joined, [5], true, true).truncated, true)
assert.strictEqual(Model.formatAge(1000, 1000 * 1000 + 5 * 60 * 1000), "5m ago")
assert.strictEqual(Model.formatAge(0, 1000), "Unknown age")

// Backoff and atomic refresh state.
assert.strictEqual(Model.failureBackoffMs(60, 0), 60000)
assert.strictEqual(Model.failureBackoffMs(60, 1), 120000)
assert.strictEqual(Model.failureBackoffMs(60, 20), Model.MAX_BACKOFF_MS)
var oldPayload = { problems: [{ eventId: "old" }], publishedMs: 1 }
var transaction = Model.beginTransaction(oldPayload)
Model.stageProblems(transaction, { problems: normalizedResult.problems, truncated: true })
assert.strictEqual(Model.canCommitTransaction(transaction), false)
var partialFailure = Model.failTransaction(transaction, "host enrichment denied", 1)
assert.strictEqual(partialFailure.published, oldPayload)
assert.strictEqual(partialFailure.stale, true)
Model.stageHosts(transaction, hostMap)
assert.strictEqual(Model.canCommitTransaction(transaction), true)
var committed = Model.commitTransaction(transaction, { version: "7.0.2", publishedMs: 5000 })
assert.strictEqual(committed.ok, true)
assert.strictEqual(committed.published.problems.length, 3)
assert.strictEqual(committed.published.problems[2].hostsAvailable, false)
assert.strictEqual(committed.published.failureStreak, 0)
var emptyTransaction = Model.beginTransaction(oldPayload)
Model.stageProblems(emptyTransaction, { problems: [], truncated: false })
assert.strictEqual(Model.canCommitTransaction(emptyTransaction), true, "empty results skip host enrichment")

// Shared state: membership, one claim, expiry, publication, and isolation.
var Shared = loadShared()
var firstSignature = Model.configurationSignature({ url: "https://one.example" }, "token-a", "/home/u")
var secondSignature = Model.configurationSignature({ url: "https://two.example" }, "token-a", "/home/u")
var members = [1, 2, 3].map(function(number) {
  return {
    name: "monitor" + number,
    received: null,
    loading: false,
    abandoned: false,
    applyShared: function(payload) { this.received = payload; this.loading = false },
    applySharedLoading: function() { this.loading = true },
    applySharedAbandoned: function() { this.loading = false; this.abandoned = true }
  }
})
for (var i = 0; i < members.length; i++) assert.strictEqual(Shared.join(firstSignature, members[i]), null)
Shared.join(firstSignature, members[0])
assert.strictEqual(Shared.memberCount(firstSignature), 3)
assert.strictEqual(Shared.claim(firstSignature, 1000, false, 60000, members[0]), true)
assert.strictEqual(members[1].loading, true, "a claim announces loading to the other monitors")
var lateLoadingMember = {
  loading: false,
  applyShared: function() {},
  applySharedLoading: function() { this.loading = true }
}
Shared.join(firstSignature, lateLoadingMember)
assert.strictEqual(lateLoadingMember.loading, true, "a late joiner adopts the in-flight state")
var claimId = Shared.currentClaim(firstSignature)
assert.strictEqual(Shared.claim(firstSignature, 1001, true, 60000, members[1]), false)
assert.strictEqual(Shared.publish(firstSignature, { problems: joined }, 2000, members[0], claimId), true)
assert.strictEqual(members[0].received, null)
assert.strictEqual(members[1].received.problems.length, 3)
assert.strictEqual(Shared.snapshot(firstSignature).problems.length, 3)
assert.strictEqual(Shared.join(firstSignature, { applyShared: function() {} }).problems.length, 3)
assert.strictEqual(Shared.snapshot(secondSignature), null)
assert.strictEqual(Shared.claim(firstSignature, 3000, false, 60000, members[1]), false, "published result is still fresh")
assert.strictEqual(Shared.claim(firstSignature, 3000, true, 60000, members[1]), true, "manual refresh bypasses freshness")
assert.strictEqual(Shared.abandon(firstSignature, members[1]), true)
assert.strictEqual(members[0].abandoned, true, "abandon releases shared loading state")
assert.strictEqual(Shared.claim(firstSignature, 4000, true, 60000, members[2]), true)
var expiredId = Shared.currentClaim(firstSignature)
assert.strictEqual(Shared.claim(firstSignature, 4000 + Model.CLAIM_TIMEOUT_MS + 1, false, 0, members[1]), true)
assert.notStrictEqual(Shared.currentClaim(firstSignature), expiredId)
assert.strictEqual(Shared.publish(firstSignature, { late: true }, 5000, members[2], expiredId), false, "expired owner cannot publish late")
assert.strictEqual(Shared.abandon(firstSignature, members[1]), true)
Shared.leave(firstSignature, members[1])
assert.strictEqual(Shared.memberCount(firstSignature), 4)

// QML wiring uses the same tested model and preserves runtime-only behavior.
var serviceSource = fs.readFileSync(path.join(__dirname, "..", "Service.qml"), "utf8")
assert.ok(serviceSource.indexOf("watchChanges: true") >= 0)
assert.ok(serviceSource.indexOf("onFileChanged: reload()") >= 0)
assert.ok(serviceSource.indexOf("onLoadFailed:") >= 0)
assert.ok(serviceSource.indexOf("onTokenChanged: scheduleConfigurationReload()") >= 0)
assert.ok(serviceSource.indexOf("command: Model.curlArgv()") >= 0)
assert.ok(serviceSource.indexOf("id: watchdog") >= 0)
assert.ok(serviceSource.indexOf("Model.beginTransaction(sharedBasePayload)") >= 0)

var panelSource = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
assert.ok(panelSource.indexOf('moduleName: "dechnik.zabbix"') >= 0)
assert.ok(panelSource.indexOf("updateEntryInline(moduleName, entry)") >= 0)
assert.ok(panelSource.indexOf("function status(): string") >= 0)
assert.strictEqual(panelSource.indexOf("zabbix.token"), -1)

console.log("model: all assertions passed")
