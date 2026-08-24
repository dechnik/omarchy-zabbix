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
  severities: "5,2,2,bad,-1",
  acknowledgement: "Acknowledged",
  acknowledgedByMe: "yes"
}, "/home/u")
assert.strictEqual(normalized.endpoint, "https://z.example/zabbix/api_jsonrpc.php")
assert.strictEqual(normalized.refreshIntervalSec, Model.MIN_REFRESH_INTERVAL_SEC)
assert.strictEqual(normalized.problemLimit, Model.MAX_PROBLEM_LIMIT)
assert.strictEqual(normalized.tokenFile, "/home/u/token")
assert.strictEqual(normalized.caCertificateFile, "/home/u/ca.pem")
assert.strictEqual(normalized.insecureTls, true)
assert.deepStrictEqual(normalized.severities, [2, 5])
assert.strictEqual(normalized.acknowledgement, "acknowledged")
assert.strictEqual(normalized.acknowledgedByMe, true)
assert.strictEqual(normalized.acknowledgedByMeActive, true)
assert.strictEqual(normalized.showSuppressed, true, "suppressed problems have always been included")
assert.strictEqual(normalized.showSymptoms, false, "a symptom beside its own cause is one incident counted twice")
assert.strictEqual(Model.normalizeSettings({ showSuppressed: "no", showSymptoms: "yes" }, "/h").showSuppressed, false)
assert.strictEqual(Model.normalizeSettings({ showSuppressed: "no", showSymptoms: "yes" }, "/h").showSymptoms, true)

// "Only acknowledged by me" is inert outside the acknowledged state.
var inertByMe = Model.normalizeSettings({ url: "https://z.example", acknowledgement: "all", acknowledgedByMe: true }, "/home/u")
assert.strictEqual(inertByMe.acknowledgedByMe, true)
assert.strictEqual(inertByMe.acknowledgedByMeActive, false)
assert.strictEqual(Model.normalizeSettings({ url: "https://z.example" }, "/home/u").acknowledgement, "all")
assert.strictEqual(Model.normalizeSettings({ url: "https://z.example", acknowledgement: "nonsense" }, "/home/u").acknowledgement, "all")

assert.strictEqual(Model.sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
assert.strictEqual(Model.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
assert.strictEqual(Model.sha256("Zażółć"), "1b45560b47f44bbf87bf66cb5d1840e833c5857f8c5656a2f42656153853f8d1")
var signature = Model.configurationSignature({ url: "https://z.example", severities: "5,4" }, "super-secret", "/home/u")
assert.strictEqual(signature.length, 64)
assert.strictEqual(signature.indexOf("super-secret"), -1)
assert.strictEqual(signature, Model.configurationSignature({ url: "https://z.example/", severities: [4, 5] }, "super-secret", "/home/u"))
assert.notStrictEqual(signature, Model.configurationSignature({ url: "https://z.example", severities: "4,5" }, "rotated", "/home/u"))
assert.notStrictEqual(
  Model.configurationSignature({ url: "https://z.example", acknowledgement: "all" }, "super-secret", "/home/u"),
  Model.configurationSignature({ url: "https://z.example", acknowledgement: "acknowledged" }, "super-secret", "/home/u"),
  "the acknowledgement state changes the request and must split the shared group")
assert.strictEqual(
  Model.configurationSignature({ url: "https://z.example", acknowledgement: "all" }, "super-secret", "/home/u"),
  Model.configurationSignature({ url: "https://z.example", acknowledgement: "All", acknowledgedByMe: true }, "super-secret", "/home/u"),
  "an inert by-me checkbox must not split the shared group")
assert.notStrictEqual(
  Model.configurationSignature({ url: "https://z.example", acknowledgement: "acknowledged" }, "super-secret", "/home/u"),
  Model.configurationSignature({ url: "https://z.example", acknowledgement: "acknowledged", acknowledgedByMe: true }, "super-secret", "/home/u"))
assert.notStrictEqual(
  Model.configurationSignature({ url: "https://z.example" }, "super-secret", "/home/u"),
  Model.configurationSignature({ url: "https://z.example", showSuppressed: false }, "super-secret", "/home/u"))
assert.notStrictEqual(
  Model.configurationSignature({ url: "https://z.example" }, "super-secret", "/home/u"),
  Model.configurationSignature({ url: "https://z.example", showSymptoms: true }, "super-secret", "/home/u"))
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
assert.deepStrictEqual(Model.buildProblemGetRequest({ severities: [5, 4, 5], rowLimit: 101 }), {
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

// The acknowledgement state maps onto problem.get's own filters.
function problemParams(options) {
  return Model.buildProblemGetRequest(options).params
}
// rowLimit is verbatim: the sweep, not the builder, owns the budget.
assert.strictEqual(problemParams({ rowLimit: 7 }).limit, 7)
assert.strictEqual(problemParams({ rowLimit: 0 }).limit, 1)
assert.strictEqual(problemParams({ rowLimit: 99999 }).limit, Model.MAX_PROBLEM_LIMIT + 1)
assert.strictEqual(problemParams({}).limit, Model.DEFAULT_PROBLEM_LIMIT + 1)

// Only the exclusions are sent; omitting a flag is what returns both kinds.
assert.strictEqual(problemParams({ showSuppressed: true }).suppressed, undefined)
assert.strictEqual(problemParams({ showSuppressed: false }).suppressed, false)
assert.strictEqual(problemParams({}).suppressed, undefined)
assert.strictEqual(problemParams({ showSymptoms: true }).symptom, undefined)
assert.strictEqual(problemParams({ showSymptoms: false }).symptom, false)
assert.strictEqual(problemParams({}).symptom, undefined)
assert.strictEqual(problemParams({ severities: [5], acknowledgement: "all" }).acknowledged, undefined)
assert.strictEqual(problemParams({ severities: [5], acknowledgement: "unacknowledged" }).acknowledged, false)
assert.strictEqual(problemParams({ severities: [5], acknowledgement: "Acknowledged" }).acknowledged, true)
assert.strictEqual(problemParams({ severities: [5], acknowledgement: "acknowledged" }).action, undefined)
var byMeParams = problemParams({ severities: [5], acknowledgement: "acknowledged", acknowledgedByUserId: "42" })
assert.strictEqual(byMeParams.acknowledged, true)
assert.strictEqual(byMeParams.action, Model.ACK_ACTION_ACKNOWLEDGE)
assert.deepStrictEqual(byMeParams.action_userids, ["42"])
// An unresolved or invalid user id drops the narrowing instead of guessing.
assert.strictEqual(problemParams({ acknowledgement: "acknowledged", acknowledgedByUserId: "0" }).action, undefined)
assert.strictEqual(problemParams({ acknowledgement: "acknowledged", acknowledgedByUserId: "" }).action_userids, undefined)
// By-me never leaks into the other two states.
assert.strictEqual(problemParams({ acknowledgement: "unacknowledged", acknowledgedByUserId: "42" }).action, undefined)
assert.strictEqual(problemParams({ acknowledgement: "all", acknowledgedByUserId: "42" }).action, undefined)

assert.deepStrictEqual(Model.buildUserCheckAuthenticationRequest("\n token-value \nignored", 4), {
  jsonrpc: "2.0", method: "user.checkAuthentication", params: { token: "token-value" }, id: 4
})
assert.throws(function() { Model.buildUserCheckAuthenticationRequest(" \n") }, /API token is empty/)
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
assert.strictEqual(Model.parseIdentityResponse('{"jsonrpc":"2.0","result":{"userid":"5","username":"ops"},"id":4}').userId, "5")
assert.strictEqual(Model.parseIdentityResponse('{"jsonrpc":"2.0","result":{"username":"ops"},"id":4}').category, "malformed-response")
assert.strictEqual(Model.parseIdentityResponse('{"jsonrpc":"2.0","result":[],"id":4}').category, "malformed-response")
var identityDenied = Model.parseIdentityResponse(JSON.stringify({
  jsonrpc: "2.0", id: 4, error: { code: -32602, message: "Invalid params.", data: 'No permissions to call "user.checkAuthentication". super-secret' }
}), 4, ["super-secret"])
assert.strictEqual(identityDenied.category, "permission")
assert.strictEqual(identityDenied.message.indexOf("super-secret"), -1)
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
assert.deepStrictEqual(Model.SEVERITIES[5], { value: 5, label: "Disaster", short: "Disaster", color: "#E45959" })
// Every severity needs a short chip label, and it must not be longer than the
// full one or the compact filter row gains nothing.
Model.SEVERITIES.forEach(function(entry) {
  assert.ok(entry.short && entry.short.length > 0)
  assert.ok(entry.short.length <= entry.label.length)
})
assert.deepStrictEqual(Model.filterProblems(joined, [5]).map(function(p) { return p.eventId }), ["2", "3"])
// Acknowledgement mirrors the server-side filter for carried-over payloads.
// Event "2" is the acknowledged row in the fixture above.
assert.deepStrictEqual(Model.filterProblems(joined, [0, 1, 2, 3, 4, 5], "acknowledged").map(function(p) { return p.eventId }), ["2"])
assert.deepStrictEqual(Model.filterProblems(joined, [0, 1, 2, 3, 4, 5], "unacknowledged").map(function(p) { return p.eventId }), ["1", "3"])
assert.strictEqual(Model.filterProblems(joined, [0, 1, 2, 3, 4, 5], "all").length, 3)
assert.strictEqual(Model.filterProblems(joined, [0, 1, 2, 3, 4, 5]).length, 3)
assert.deepStrictEqual(Model.filterProblems(joined, [4], "acknowledged").map(function(p) { return p.eventId }), [])
assert.strictEqual(Model.severitySummary(joined, [0, 1, 2, 3, 4, 5], true, false, "unacknowledged").count, 1)
assert.strictEqual(Model.severitySummary(joined, [0, 1, 2, 3, 4, 5], true, false, "unacknowledged").severity, 5)
assert.strictEqual(Model.severitySummary(joined, [0, 1, 2, 3, 4, 5], true, false, "acknowledged").count, 1)
assert.strictEqual(Model.highestSeveritySummary(joined, [4], { available: true, acknowledgement: "acknowledged" }).count, 0)

assert.strictEqual(Model.parseAcknowledgement("Unacknowledged"), "unacknowledged")
assert.strictEqual(Model.parseAcknowledgement("  ACK  "), "acknowledged")
assert.strictEqual(Model.parseAcknowledgement("unack"), "unacknowledged")
assert.strictEqual(Model.parseAcknowledgement(""), "all")
assert.strictEqual(Model.parseAcknowledgement(undefined), "all")
assert.strictEqual(Model.parseAcknowledgement("sometimes"), "all")
assert.strictEqual(Model.persistAcknowledgement("ack"), "Acknowledged")
assert.strictEqual(Model.persistAcknowledgement("nonsense"), "All")
assert.strictEqual(Model.parseAcknowledgement(Model.persistAcknowledgement("unack")), "unacknowledged")
assert.strictEqual(Model.ACKNOWLEDGEMENTS.length, 3)
assert.deepStrictEqual(Model.ACKNOWLEDGEMENTS.map(function(entry) { return entry.value }), ["all", "unacknowledged", "acknowledged"])
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

// Severity sweep: problem.get can only sort by eventid, so the retained set is
// built highest-severity-first instead of newest-first.
function runSweep(severities, problemLimit, available) {
  var sweep = Model.beginSeveritySweep(severities, problemLimit)
  var steps = []
  var guard = 0
  while (!Model.sweepComplete(sweep)) {
    if (++guard > 20) throw new Error("sweep did not terminate")
    var severity = Model.sweepSeverity(sweep)
    var rowLimit = Model.sweepRowLimit(sweep)
    steps.push({ severity: severity, rowLimit: rowLimit })
    var take = Math.min(available[severity] || 0, rowLimit)
    var rows = []
    for (var i = 0; i < take; i++) {
      rows.push({ eventid: String(severity * 10000 + i), objectid: "1", clock: "1", severity: String(severity) })
    }
    Model.stageSweepRows(sweep, rows)
  }
  return { steps: steps, sweep: sweep }
}

// The real distribution measured on a live 7.0.6 server: 227 problems, of which
// only the top 100 by severity may be kept.
var busy = runSweep([0, 1, 2, 3, 4, 5], 100, { 5: 1, 4: 25, 3: 83, 2: 63, 1: 39, 0: 16 })
assert.deepStrictEqual(busy.steps, [
  { severity: 5, rowLimit: 101 },
  { severity: 4, rowLimit: 100 },
  { severity: 3, rowLimit: 75 }
], "Disaster first, and the budget shrinks by what each severity returned")
var busyResult = Model.normalizeProblemResult(busy.sweep.rows, 100)
assert.strictEqual(busyResult.problems.length, 100)
assert.strictEqual(busyResult.truncated, true)
assert.strictEqual(busyResult.problems[0].severity, 5, "the most severe problem survives the limit")
assert.strictEqual(Model.filterProblems(busyResult.problems, [4]).length, 25, "every High is retained, not just the newest")

// A quiet server never fills the budget, so it visits every selected severity
// and reports no truncation.
var quiet = runSweep([0, 1, 2, 3, 4, 5], 100, { 5: 0, 4: 2, 3: 3, 2: 0, 1: 1, 0: 0 })
assert.deepStrictEqual(quiet.steps.map(function(step) { return step.severity }), [5, 4, 3, 2, 1, 0])
assert.strictEqual(Model.normalizeProblemResult(quiet.sweep.rows, 100).truncated, false)
assert.strictEqual(quiet.sweep.rows.length, 6)

// Deselected severities are never requested at all.
var narrow = runSweep([4, 5], 100, { 5: 1, 4: 25, 3: 83 })
assert.deepStrictEqual(narrow.steps.map(function(step) { return step.severity }), [5, 4])

// A single severity that overflows the budget stops the sweep immediately.
var flood = runSweep([0, 1, 2, 3, 4, 5], 10, { 5: 400 })
assert.deepStrictEqual(flood.steps, [{ severity: 5, rowLimit: 11 }])
assert.strictEqual(Model.normalizeProblemResult(flood.sweep.rows, 10).truncated, true)

// An empty sweep is complete and safe to interrogate.
var emptySweep = Model.beginSeveritySweep([5], 0)
assert.strictEqual(Model.sweepSeverity(emptySweep), 5)
assert.strictEqual(Model.sweepComplete(null), true)
assert.strictEqual(Model.sweepSeverity(null), null)

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
// The identity call must stay unauthenticated: the token travels in the body.
assert.ok(/startRequest\("identity",[^)]*, false\)/.test(serviceSource))
assert.ok(serviceSource.indexOf('startRequest("problems", Model.buildProblemGetRequest({') >= 0)
// The sweep must drive the problem phase, one severity at a time.
assert.ok(serviceSource.indexOf("Model.beginSeveritySweep(selectedSeverities, normalized.problemLimit)") >= 0)
assert.ok(serviceSource.indexOf("severities: [Model.sweepSeverity(sweep)]") >= 0)
assert.ok(serviceSource.indexOf("rowLimit: Model.sweepRowLimit(sweep)") >= 0)
assert.ok(serviceSource.indexOf("Model.stageSweepRows(sweep, problemResponse.result)") >= 0)
// A partial sweep must never leak into the next refresh, on any exit path.
function serviceFunctionBody(name) {
  var start = serviceSource.indexOf("function " + name + "(")
  assert.ok(start >= 0, name + " must exist in Service.qml")
  var next = serviceSource.indexOf("\n    function ", start + 1)
  return next < 0 ? serviceSource.slice(start) : serviceSource.slice(start, next)
}
["finishProblems", "finishSuccess", "failRefresh", "cancelRequest"].forEach(function(name) {
  assert.ok(serviceFunctionBody(name).indexOf("sweep = null") >= 0, name + " must clear the sweep")
})
assert.ok(serviceSource.indexOf("acknowledgedByUserId: acknowledgedByMe ? resolvedUserId() : \"\"") >= 0)

var panelSource = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
assert.ok(panelSource.indexOf('moduleName: "dechnik.zabbix"') >= 0)
assert.ok(panelSource.indexOf("updateEntryInline(moduleName, entry)") >= 0)
assert.ok(panelSource.indexOf("function status(): string") >= 0)
assert.strictEqual(panelSource.indexOf("zabbix.token"), -1)
assert.ok(panelSource.indexOf("Model.ACKNOWLEDGEMENTS") >= 0)
assert.ok(panelSource.indexOf("Model.persistAcknowledgement(next)") >= 0)
// The by-me control must stay inert unless the acknowledged state is selected.
assert.ok(panelSource.indexOf("enabled: root.acknowledgedByMeEnabled") >= 0)
assert.ok(panelSource.indexOf('acknowledgedByMeEnabled: acknowledgement === "acknowledged"') >= 0)
// Warnings and filters collapse so the problem list gets the panel's height,
// and the disclosure state is panel-local: every open starts collapsed.
assert.ok(panelSource.indexOf("component DisclosureHeader") >= 0)
// Severity and acknowledgement live under one FILTERS disclosure, each row
// captioned so the chips are not an unlabelled pile.
assert.ok(panelSource.indexOf('text: "Severity"') >= 0)
assert.ok(panelSource.indexOf('text: "Acknowledgement"') >= 0)
assert.ok(panelSource.indexOf("component FilterGroupLabel") >= 0)
assert.ok(/onOpenedChanged: if \(opened\) \{[^}]*noticesExpanded = false;[^}]*filtersExpanded = false;/.test(panelSource))
// Progress state lives on the hero meta line, not in a banner.
assert.strictEqual(panelSource.indexOf("Refreshing problems; the last complete result remains visible."), -1)
assert.strictEqual(panelSource.indexOf("Waiting for the first problem refresh."), -1)

var manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
assert.strictEqual(manifest.barWidget.defaults.acknowledgement, "All")
assert.strictEqual(manifest.barWidget.defaults.acknowledgedByMe, false)
var schemaKeys = manifest.barWidget.schema.map(function(field) { return field.key })
// Disclosure state is panel-local, never a persisted setting.
assert.strictEqual(schemaKeys.indexOf("filtersExpanded"), -1)
assert.strictEqual(schemaKeys.indexOf("noticesExpanded"), -1)
assert.ok(schemaKeys.indexOf("showSuppressed") >= 0)
assert.ok(schemaKeys.indexOf("showSymptoms") >= 0)
assert.strictEqual(manifest.barWidget.defaults.showSuppressed, true)
assert.strictEqual(manifest.barWidget.defaults.showSymptoms, false)
assert.ok(schemaKeys.indexOf("acknowledgement") >= 0)
assert.ok(schemaKeys.indexOf("acknowledgedByMe") >= 0)
manifest.barWidget.schema.forEach(function(field) {
  if (field.key !== "acknowledgement") return
  // The shell renders enum options as plain strings, so every option must
  // survive a parse/persist round trip or the form and the panel disagree.
  assert.strictEqual(field.type, "enum")
  field.options.forEach(function(option) {
    assert.strictEqual(Model.persistAcknowledgement(option), option)
  })
  assert.strictEqual(Model.persistAcknowledgement(field.defaultValue), field.defaultValue)
})

console.log("model: all assertions passed")
