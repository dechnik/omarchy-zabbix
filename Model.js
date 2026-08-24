// Pure, QML-compatible helpers for the Zabbix bar plugin. Keep this file free
// of QML dependencies so the exact runtime code can also be tested with Node.

var DEFAULT_TOKEN_FILE = "~/.config/omarchy/zabbix/token"
var DEFAULT_REFRESH_INTERVAL_SEC = 60
var MIN_REFRESH_INTERVAL_SEC = 15
var MAX_REFRESH_INTERVAL_SEC = 3600
var DEFAULT_PROBLEM_LIMIT = 100
var MIN_PROBLEM_LIMIT = 1
var MAX_PROBLEM_LIMIT = 1000
var DEFAULT_CONNECT_TIMEOUT_SEC = 5
var DEFAULT_TOTAL_TIMEOUT_SEC = 12
var MAX_BACKOFF_MS = 900000
var CLAIM_TIMEOUT_MS = 45000
var CURL_STATUS_MARKER = "__ZABBIX_HTTP_STATUS__:"

var PROBLEM_OUTPUT = [
  "eventid", "objectid", "clock", "name", "severity",
  "acknowledged", "suppressed", "cause_eventid"
]

var ACKNOWLEDGEMENTS = [
  { value: "all", label: "All" },
  { value: "unacknowledged", label: "Unacknowledged" },
  { value: "acknowledged", label: "Acknowledged" }
]

// Zabbix event update action bitmask; 2 selects the acknowledge action.
var ACK_ACTION_ACKNOWLEDGE = 2

// `short` keeps the six filter chips on one row of the panel; `label` is what
// a problem row and every message says.
var SEVERITIES = [
  { value: 0, label: "Not classified", short: "NC", color: "#97AAB3" },
  { value: 1, label: "Information", short: "Info", color: "#7499FF" },
  { value: 2, label: "Warning", short: "Warn", color: "#FFC859" },
  { value: 3, label: "Average", short: "Avg", color: "#FFA059" },
  { value: 4, label: "High", short: "High", color: "#E97659" },
  { value: 5, label: "Disaster", short: "Disaster", color: "#E45959" }
]

function text(value) {
  return String(value === undefined || value === null ? "" : value)
}

function trim(value) {
  return text(value).replace(/^\s+|\s+$/g, "")
}

function clampInteger(value, fallback, minimum, maximum) {
  var number = Number(value)
  if (!isFinite(number)) number = fallback
  number = Math.round(number)
  if (number < minimum) number = minimum
  if (number > maximum) number = maximum
  return number
}

function boolValue(value, fallback) {
  if (value === true || value === false) return value
  var normalized = trim(value).toLowerCase()
  if (normalized === "true" || normalized === "1" || normalized === "yes" || normalized === "on") return true
  if (normalized === "false" || normalized === "0" || normalized === "no" || normalized === "off") return false
  return fallback === true
}

function expandHome(path, home) {
  var value = trim(path)
  var base = text(home).replace(/\/$/, "")
  if (value === "") return ""
  if (value === "~") return base
  if (value.indexOf("~/") === 0) return base + value.substring(1)
  return value
}

function firstNonEmptyLine(contents) {
  var lines = text(contents).split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = trim(lines[i])
    if (line !== "") return line
  }
  return ""
}

function endpointError(value) {
  var input = trim(value)
  if (input === "") return "Zabbix URL is not configured"
  if (!/^https:\/\//i.test(input)) return "Zabbix URL must use HTTPS"
  if (/^https:\/\/[^\/]*@/i.test(input)) return "Zabbix URL must not contain credentials"
  if (!/^https:\/\/[^\s\/?#]+(?::\d+)?(?:[\/?#]|$)/i.test(input)) return "Zabbix URL is invalid"
  if (/[\r\n]/.test(input)) return "Zabbix URL is invalid"
  if (/[?#]/.test(input)) return "Zabbix URL must not contain a query or fragment"
  return ""
}

function normalizeEndpoint(value) {
  var input = trim(value)
  if (endpointError(input) !== "") return ""
  input = input.replace(/\/+$/, "")
  if (/\/api_jsonrpc\.php$/i.test(input)) return input
  return input + "/api_jsonrpc.php"
}

function isHttpsEndpoint(value) {
  return normalizeEndpoint(value) !== ""
}

function severityValues() {
  var values = []
  for (var i = 0; i < SEVERITIES.length; i++) values.push(SEVERITIES[i].value)
  return values
}

function parseSeveritySelection(raw, fallback) {
  var parts
  if (raw instanceof Array) parts = raw
  else parts = text(raw).split(",")
  var selected = []
  var seen = {}
  for (var i = 0; i < parts.length; i++) {
    var token = trim(parts[i])
    if (!/^\d+$/.test(token)) continue
    var value = Number(token)
    if (value < 0 || value > 5 || seen[value]) continue
    seen[value] = true
    selected.push(value)
  }
  selected.sort(function(a, b) { return a - b })
  if (selected.length > 0) return selected
  if (fallback !== undefined && fallback !== raw) return parseSeveritySelection(fallback)
  return severityValues()
}

function persistSeveritySelection(selection, previous) {
  var parsed = parseSeveritySelection(selection, previous)
  return parsed.join(",")
}

function toggleSeverity(selection, severity) {
  var current = parseSeveritySelection(selection)
  var value = Number(severity)
  if (value < 0 || value > 5 || Math.floor(value) !== value) return current
  var index = current.indexOf(value)
  if (index >= 0) {
    if (current.length === 1) return current
    current.splice(index, 1)
  } else {
    current.push(value)
    current.sort(function(a, b) { return a - b })
  }
  return current
}

function severityDefinition(value) {
  var number = Number(value)
  return number >= 0 && number < SEVERITIES.length && Math.floor(number) === number
    ? SEVERITIES[number] : null
}

// The generated settings form stores an enum option's label, while the CLI
// writes whatever the user typed. Parsing accepts both plus the obvious
// shorthands; persistence always writes the label back.
var ACKNOWLEDGEMENT_ALIASES = {
  "": "all",
  "all": "all",
  "any": "all",
  "unacknowledged": "unacknowledged",
  "unacknowledge": "unacknowledged",
  "unack": "unacknowledged",
  "not-acknowledged": "unacknowledged",
  "false": "unacknowledged",
  "0": "unacknowledged",
  "acknowledged": "acknowledged",
  "acknowledge": "acknowledged",
  "ack": "acknowledged",
  "true": "acknowledged",
  "1": "acknowledged"
}

function acknowledgementDefinition(value) {
  var canonical = parseAcknowledgement(value)
  for (var i = 0; i < ACKNOWLEDGEMENTS.length; i++) {
    if (ACKNOWLEDGEMENTS[i].value === canonical) return ACKNOWLEDGEMENTS[i]
  }
  return ACKNOWLEDGEMENTS[0]
}

function parseAcknowledgement(raw) {
  var token = trim(raw).toLowerCase()
  var matched = ACKNOWLEDGEMENT_ALIASES[token]
  return matched === undefined ? "all" : matched
}

function persistAcknowledgement(value) {
  return acknowledgementDefinition(value).label
}

function normalizeSettings(settings, home) {
  var source = settings || {}
  var endpoint = normalizeEndpoint(source.url === undefined ? source.endpoint : source.url)
  var severities = parseSeveritySelection(source.severities)
  var acknowledgement = parseAcknowledgement(source.acknowledgement)
  var acknowledgedByMe = boolValue(source.acknowledgedByMe, false)
  return {
    url: endpoint,
    endpoint: endpoint,
    endpointError: endpointError(source.url === undefined ? source.endpoint : source.url),
    tokenFile: expandHome(source.tokenFile === undefined ? DEFAULT_TOKEN_FILE : source.tokenFile, home),
    caCertificateFile: expandHome(source.caCertificateFile, home),
    insecureTls: boolValue(source.insecureTls, false),
    refreshIntervalSec: clampInteger(source.refreshIntervalSec, DEFAULT_REFRESH_INTERVAL_SEC, MIN_REFRESH_INTERVAL_SEC, MAX_REFRESH_INTERVAL_SEC),
    problemLimit: clampInteger(source.problemLimit, DEFAULT_PROBLEM_LIMIT, MIN_PROBLEM_LIMIT, MAX_PROBLEM_LIMIT),
    severities: severities,
    severitySetting: severities.join(","),
    acknowledgement: acknowledgement,
    acknowledgedByMe: acknowledgedByMe,
    // "Only acknowledged by me" refines the acknowledged state; it is inert on
    // the other two states, so only the effective flag reaches the request and
    // the configuration signature.
    acknowledgedByMeActive: acknowledgement === "acknowledged" && acknowledgedByMe
  }
}

// Pure SHA-256. It deliberately returns only the digest; configuration keys
// never retain token text in a shared object or serialized setting.
function utf8Bytes(value) {
  var input = text(value)
  var bytes = []
  for (var i = 0; i < input.length; i++) {
    var code = input.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < input.length) {
      var low = input.charCodeAt(i + 1)
      if (low >= 0xdc00 && low <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00)
        i += 1
      }
    }
    if (code < 0x80) bytes.push(code)
    else if (code < 0x800) {
      bytes.push(0xc0 | (code >>> 6), 0x80 | (code & 63))
    } else if (code < 0x10000) {
      bytes.push(0xe0 | (code >>> 12), 0x80 | ((code >>> 6) & 63), 0x80 | (code & 63))
    } else {
      bytes.push(0xf0 | (code >>> 18), 0x80 | ((code >>> 12) & 63), 0x80 | ((code >>> 6) & 63), 0x80 | (code & 63))
    }
  }
  return bytes
}

function rotateRight(value, amount) {
  return (value >>> amount) | (value << (32 - amount))
}

function hex32(value) {
  return ("00000000" + (value >>> 0).toString(16)).slice(-8)
}

function sha256(value) {
  var bytes = utf8Bytes(value)
  var bitHigh = Math.floor(bytes.length / 0x20000000)
  var bitLow = (bytes.length << 3) >>> 0
  bytes.push(0x80)
  while (bytes.length % 64 !== 56) bytes.push(0)
  bytes.push((bitHigh >>> 24) & 255, (bitHigh >>> 16) & 255, (bitHigh >>> 8) & 255, bitHigh & 255)
  bytes.push((bitLow >>> 24) & 255, (bitLow >>> 16) & 255, (bitLow >>> 8) & 255, bitLow & 255)

  var constants = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]
  var hash = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
  var words = new Array(64)
  for (var offset = 0; offset < bytes.length; offset += 64) {
    for (var w = 0; w < 16; w++) {
      var p = offset + w * 4
      words[w] = ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]) | 0
    }
    for (var x = 16; x < 64; x++) {
      var s0 = rotateRight(words[x - 15], 7) ^ rotateRight(words[x - 15], 18) ^ (words[x - 15] >>> 3)
      var s1 = rotateRight(words[x - 2], 17) ^ rotateRight(words[x - 2], 19) ^ (words[x - 2] >>> 10)
      words[x] = (words[x - 16] + s0 + words[x - 7] + s1) | 0
    }
    var a = hash[0]
    var b = hash[1]
    var c = hash[2]
    var d = hash[3]
    var e = hash[4]
    var f = hash[5]
    var g = hash[6]
    var h = hash[7]
    for (var round = 0; round < 64; round++) {
      var big1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
      var choose = (e & f) ^ ((~e) & g)
      var first = (h + big1 + choose + constants[round] + words[round]) | 0
      var big0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
      var majority = (a & b) ^ (a & c) ^ (b & c)
      var second = (big0 + majority) | 0
      h = g
      g = f
      f = e
      e = (d + first) | 0
      d = c
      c = b
      b = a
      a = (first + second) | 0
    }
    hash[0] = (hash[0] + a) | 0
    hash[1] = (hash[1] + b) | 0
    hash[2] = (hash[2] + c) | 0
    hash[3] = (hash[3] + d) | 0
    hash[4] = (hash[4] + e) | 0
    hash[5] = (hash[5] + f) | 0
    hash[6] = (hash[6] + g) | 0
    hash[7] = (hash[7] + h) | 0
  }
  var output = ""
  for (var i = 0; i < hash.length; i++) output += hex32(hash[i])
  return output
}

function configurationSignature(settings, token, home) {
  var normalized = normalizeSettings(settings, home)
  var material = [
    normalized.endpoint,
    normalized.tokenFile,
    normalized.caCertificateFile,
    normalized.insecureTls ? "1" : "0",
    String(normalized.refreshIntervalSec),
    String(normalized.problemLimit),
    normalized.severitySetting,
    normalized.acknowledgement,
    normalized.acknowledgedByMeActive ? "1" : "0",
    sha256(text(token))
  ].join("\u0000")
  return sha256(material)
}

function dataSourceSignature(settings, token, home) {
  var normalized = normalizeSettings(settings, home)
  return sha256(normalized.endpoint + "\u0000" + sha256(text(token)))
}

function parseVersion(value) {
  var raw = trim(value)
  var match = raw.match(/^(\d+)\.(\d+)(?:\.(\d+))?(?:[-.]?(?:alpha|beta|rc)\d*)?$/i)
  if (!match) return null
  return { raw: raw, major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3] || 0) }
}

function compareVersions(left, right) {
  var a = typeof left === "string" ? parseVersion(left) : left
  var b = typeof right === "string" ? parseVersion(right) : right
  if (!a || !b) return null
  if (a.major !== b.major) return a.major < b.major ? -1 : 1
  if (a.minor !== b.minor) return a.minor < b.minor ? -1 : 1
  if (a.patch !== b.patch) return a.patch < b.patch ? -1 : 1
  return 0
}

function isSupportedVersion(value) {
  var parsed = parseVersion(value)
  return parsed !== null && compareVersions(parsed, { major: 7, minor: 0, patch: 0 }) >= 0
}

// Values interpolated into curl's quoted configuration grammar must reject
// line breaks, not merely remove them, or a caller could add a new directive.
function curlConfigEscape(value) {
  var raw = text(value)
  if (/[\r\n]/.test(raw)) throw new Error("curl configuration values must not contain line breaks")
  return raw.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
}

var FETCH_SCRIPT = [
  "set -eu",
  "{",
  "  printf '%s\\n' 'url = \"'\"$ZABBIX_URL\"'\"'",
  "  printf '%s\\n' 'request = \"POST\"'",
  "  printf '%s\\n' 'header = \"Content-Type: application/json\"'",
  "  if [ \"$ZABBIX_AUTH\" = 1 ]; then printf '%s\\n' 'header = \"Authorization: Bearer '\"$ZABBIX_TOKEN\"'\"'; fi",
  "  printf '%s\\n' 'data = \"'\"$ZABBIX_BODY\"'\"'",
  "  printf '%s\\n' 'connect-timeout = \"'\"$ZABBIX_CONNECT_TIMEOUT\"'\"'",
  "  printf '%s\\n' 'max-time = \"'\"$ZABBIX_TOTAL_TIMEOUT\"'\"'",
  "  if [ -n \"$ZABBIX_CA_FILE\" ]; then printf '%s\\n' 'cacert = \"'\"$ZABBIX_CA_FILE\"'\"'; fi",
  "  if [ \"$ZABBIX_INSECURE\" = 1 ]; then printf '%s\\n' 'insecure'; fi",
  "  printf '%s\\n' 'write-out = \"\\n" + CURL_STATUS_MARKER + "%{http_code}\"'",
  "} | curl --silent --show-error --fail-with-body --config -"
].join("\n")

function curlArgv() {
  return ["bash", "-c", FETCH_SCRIPT]
}

function buildCurlEnvironment(endpoint, body, token, options) {
  var config = options || {}
  var url = normalizeEndpoint(endpoint)
  if (url === "") throw new Error(endpointError(endpoint))
  var authenticated = config.authenticated === true
  if (authenticated && firstNonEmptyLine(token) === "") throw new Error("API token is empty")
  var connectTimeout = clampInteger(config.connectTimeoutSec, DEFAULT_CONNECT_TIMEOUT_SEC, 1, 60)
  var totalTimeout = clampInteger(config.totalTimeoutSec, DEFAULT_TOTAL_TIMEOUT_SEC, connectTimeout, 120)
  return {
    ZABBIX_URL: curlConfigEscape(url),
    ZABBIX_BODY: curlConfigEscape(body),
    ZABBIX_TOKEN: authenticated ? curlConfigEscape(firstNonEmptyLine(token)) : "",
    ZABBIX_AUTH: authenticated ? "1" : "0",
    ZABBIX_CA_FILE: curlConfigEscape(config.caCertificateFile || ""),
    ZABBIX_INSECURE: config.insecureTls === true ? "1" : "0",
    ZABBIX_CONNECT_TIMEOUT: String(connectTimeout),
    ZABBIX_TOTAL_TIMEOUT: String(totalTimeout)
  }
}

function request(id, method, params) {
  return { jsonrpc: "2.0", method: method, params: params, id: id }
}

function buildApiInfoVersionRequest(id) {
  return request(id === undefined ? 1 : id, "apiinfo.version", {})
}

function buildProblemGetRequest(options, id) {
  var config = options || {}
  var selected = parseSeveritySelection(config.severities)
  var limit = clampInteger(config.problemLimit, DEFAULT_PROBLEM_LIMIT, MIN_PROBLEM_LIMIT, MAX_PROBLEM_LIMIT)
  var acknowledgement = parseAcknowledgement(config.acknowledgement)
  var params = {
    output: PROBLEM_OUTPUT.slice(),
    selectTags: ["tag", "value"],
    source: 0,
    object: 0,
    recent: false,
    severities: selected,
    sortfield: ["eventid"],
    sortorder: "DESC",
    limit: limit + 1
  }
  if (acknowledgement === "unacknowledged") params.acknowledged = false
  else if (acknowledgement === "acknowledged") {
    params.acknowledged = true
    // Without a resolved user id the "by me" narrowing is dropped rather than
    // guessed; the panel says so instead of silently hiding other people's work.
    var userId = idString(config.acknowledgedByUserId)
    if (userId !== "") {
      params.action = ACK_ACTION_ACKNOWLEDGE
      params.action_userids = [userId]
    }
  }
  return request(id === undefined ? 2 : id, "problem.get", params)
}

function buildUserCheckAuthenticationRequest(token, id) {
  var value = firstNonEmptyLine(token)
  if (value === "") throw new Error("API token is empty")
  return request(id === undefined ? 4 : id, "user.checkAuthentication", { token: value })
}

function uniqueIds(values) {
  var seen = {}
  var output = []
  for (var i = 0; i < (values || []).length; i++) {
    var value = values[i] && values[i].triggerId !== undefined ? values[i].triggerId : values[i]
    var id = trim(value)
    if (!/^\d+$/.test(id) || id === "0" || seen[id]) continue
    seen[id] = true
    output.push(id)
  }
  return output
}

function buildTriggerGetRequest(triggerIds, id) {
  return request(id === undefined ? 3 : id, "trigger.get", {
    output: ["triggerid"],
    triggerids: uniqueIds(triggerIds),
    selectHosts: ["hostid", "name"]
  })
}

function requestBody(value) {
  return JSON.stringify(value)
}

function safeMessage(value, secrets) {
  var output = text(value).replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  for (var i = 0; i < (secrets || []).length; i++) {
    var secret = text(secrets[i])
    if (secret === "") continue
    output = output.split(secret).join("[redacted]")
  }
  output = output.replace(/Authorization:\s*Bearer\s+\S+/ig, "Authorization: Bearer [redacted]")
  if (output.length > 240) output = output.substring(0, 237) + "..."
  return output
}

function errorResult(category, message, code) {
  return { ok: false, category: category, message: message, code: code === undefined ? null : code }
}

function parseCurlOutput(stdout) {
  var output = text(stdout)
  var marker = "\n" + CURL_STATUS_MARKER
  var index = output.lastIndexOf(marker)
  if (index < 0) return { ok: false, body: output, status: 0, error: "missing HTTP status marker" }
  var statusText = trim(output.substring(index + marker.length))
  if (!/^\d{3}$/.test(statusText)) return { ok: false, body: output.substring(0, index), status: 0, error: "invalid HTTP status marker" }
  return { ok: true, body: output.substring(0, index), status: Number(statusText), error: "" }
}

function classifyHttpStatus(status) {
  var code = Number(status)
  if (code >= 300 && code < 400) return errorResult("endpoint", "Zabbix API redirected the request; configure the final HTTPS URL", code)
  if (code === 401) return errorResult("authentication", "Zabbix rejected the API token", code)
  if (code === 403) return errorResult("permission", "Zabbix denied access to the API", code)
  if (code === 404) return errorResult("endpoint", "Zabbix API endpoint was not found", code)
  if (code === 408 || code === 504) return errorResult("timeout", "Zabbix request timed out", code)
  if (code >= 500) return errorResult("http", "Zabbix server returned HTTP " + code, code)
  return errorResult("http", "Zabbix returned HTTP " + code, code)
}

function classifyCurlResult(exitCode, stdout, stderr, secrets) {
  var code = Number(exitCode)
  var parsed = parseCurlOutput(stdout)
  if (parsed.ok && parsed.status >= 300) return classifyHttpStatus(parsed.status)
  if (code === 0 && parsed.ok) return { ok: true, category: "", message: "", code: 0, status: parsed.status, body: parsed.body }
  if (code === 3) return errorResult("endpoint", "Zabbix API endpoint is invalid", code)
  if (code === 5 || code === 6) return errorResult("network", "Cannot resolve the Zabbix server", code)
  if (code === 7) return errorResult("network", "Cannot reach the Zabbix server", code)
  if (code === 28 || code === 124) return errorResult("timeout", "Zabbix request timed out", code)
  if ([35, 51, 53, 58, 59, 60, 77, 80, 82, 83, 90, 91].indexOf(code) >= 0) return errorResult("tls", "TLS verification or handshake with Zabbix failed", code)
  if (code === 127) return errorResult("transport", "curl is not installed", code)
  var message = safeMessage(stderr, secrets)
  return errorResult(parsed.ok ? "transport" : "malformed-response", message || (parsed.error || "Zabbix request failed"), code)
}

function classifyJsonRpcError(error, method, secrets) {
  var source = error || {}
  var detail = safeMessage([source.message, source.data].join(" "), secrets)
  var lower = detail.toLowerCase()
  var capability = trim(method) || "required API method"
  if (/permission|not allowed|denied|no permissions|method not found/.test(lower) || Number(source.code) === -32601) {
    return errorResult("permission", "Zabbix permission does not allow " + capability, source.code)
  }
  if (/not authorized|not authorised|authentication|api token|session terminated|re-login|not logged in/.test(lower)) {
    return errorResult("authentication", "Zabbix rejected the API token", source.code)
  }
  return errorResult("json-rpc", detail || "Zabbix returned a JSON-RPC error", source.code)
}

function parseJsonRpcResponse(raw, expectedId, method, secrets) {
  var payload
  try {
    payload = JSON.parse(text(raw))
  } catch (exception) {
    return errorResult("malformed-response", "Zabbix returned unreadable JSON", null)
  }
  if (!payload || typeof payload !== "object" || payload instanceof Array || payload.jsonrpc !== "2.0") {
    return errorResult("malformed-response", "Zabbix returned an invalid JSON-RPC response", null)
  }
  if (expectedId !== undefined && String(payload.id) !== String(expectedId)) {
    return errorResult("malformed-response", "Zabbix returned a mismatched JSON-RPC response", null)
  }
  if (payload.error) return classifyJsonRpcError(payload.error, method, secrets)
  if (!("result" in payload)) return errorResult("malformed-response", "Zabbix response has no result", null)
  return { ok: true, category: "", message: "", code: null, result: payload.result }
}

function parseVersionResponse(raw, expectedId) {
  var parsed = parseJsonRpcResponse(raw, expectedId === undefined ? 1 : expectedId, "apiinfo.version")
  if (!parsed.ok) return parsed
  var version = parseVersion(parsed.result)
  if (!version) return errorResult("malformed-response", "Zabbix returned an invalid API version", null)
  if (!isSupportedVersion(parsed.result)) return errorResult("version", "Zabbix " + version.raw + " is unsupported; version 7.0 or newer is required", null)
  return { ok: true, category: "", message: "", code: null, result: version.raw, version: version }
}

function parseIdentityResponse(raw, expectedId, secrets) {
  var parsed = parseJsonRpcResponse(raw, expectedId === undefined ? 4 : expectedId, "user.checkAuthentication", secrets)
  if (!parsed.ok) return parsed
  var result = parsed.result
  var userId = result && typeof result === "object" && !(result instanceof Array) ? idString(result.userid) : ""
  if (userId === "") return errorResult("malformed-response", "Zabbix did not return the API token's user", null)
  return { ok: true, category: "", message: "", code: null, result: userId, userId: userId }
}

function idString(value) {
  var output = trim(value)
  return /^\d+$/.test(output) && output !== "0" ? output : ""
}

function flag(value) {
  return value === true || value === 1 || value === "1" || trim(value).toLowerCase() === "true"
}

function normalizeTags(tags) {
  var output = []
  for (var i = 0; i < (tags instanceof Array ? tags.length : 0); i++) {
    var tag = tags[i]
    if (!tag || typeof tag !== "object") continue
    var name = trim(tag.tag)
    var value = trim(tag.value)
    if (name === "" && value === "") continue
    output.push({ tag: name, value: value })
  }
  return output
}

function normalizeProblem(raw) {
  if (!raw || typeof raw !== "object") return null
  var eventId = idString(raw.eventid)
  var triggerId = idString(raw.objectid)
  var severity = Number(raw.severity)
  var clock = Number(raw.clock)
  if (eventId === "" || triggerId === "" || Math.floor(severity) !== severity || severity < 0 || severity > 5) return null
  if (!isFinite(clock) || clock < 0) clock = 0
  clock = Math.floor(clock)
  var cause = idString(raw.cause_eventid)
  return {
    eventId: eventId,
    triggerId: triggerId,
    name: trim(raw.name) || "Unnamed problem",
    clock: clock,
    timestampMs: clock * 1000,
    severity: severity,
    acknowledged: flag(raw.acknowledged),
    suppressed: flag(raw.suppressed),
    causeEventId: cause,
    isSymptom: cause !== "",
    tags: normalizeTags(raw.tags),
    hosts: [],
    hostNames: [],
    hostsAvailable: false
  }
}

function normalizeProblemResult(rows, problemLimit) {
  var source = rows instanceof Array ? rows : []
  var limit = clampInteger(problemLimit, DEFAULT_PROBLEM_LIMIT, MIN_PROBLEM_LIMIT, MAX_PROBLEM_LIMIT)
  var output = []
  for (var i = 0; i < source.length && output.length < limit; i++) {
    var problem = normalizeProblem(source[i])
    if (problem) output.push(problem)
  }
  return { problems: output, truncated: source.length > limit }
}

function normalizeHosts(rows) {
  var map = {}
  for (var i = 0; i < (rows instanceof Array ? rows.length : 0); i++) {
    var row = rows[i]
    if (!row || typeof row !== "object") continue
    var triggerId = idString(row.triggerid)
    if (triggerId === "") continue
    var hosts = []
    var seen = {}
    for (var h = 0; h < (row.hosts instanceof Array ? row.hosts.length : 0); h++) {
      var source = row.hosts[h]
      if (!source || typeof source !== "object") continue
      var hostId = idString(source.hostid)
      var name = trim(source.name)
      var key = hostId || name
      if (key === "" || seen[key]) continue
      seen[key] = true
      hosts.push({ hostId: hostId, name: name || "Unnamed host" })
    }
    map[triggerId] = hosts
  }
  return map
}

function copyObject(source) {
  var output = {}
  for (var key in source) {
    if (Object.prototype.hasOwnProperty.call(source, key)) output[key] = source[key]
  }
  return output
}

function joinProblemHosts(problems, hostMap) {
  var output = []
  var map = hostMap || {}
  for (var i = 0; i < (problems || []).length; i++) {
    var problem = copyObject(problems[i])
    var available = Object.prototype.hasOwnProperty.call(map, problem.triggerId)
    var hosts = available && map[problem.triggerId] instanceof Array ? map[problem.triggerId].slice() : []
    var names = []
    for (var h = 0; h < hosts.length; h++) names.push(hosts[h].name)
    problem.hosts = hosts
    problem.hostNames = names
    problem.hostsAvailable = available
    problem.hostLabel = available ? (names.length > 0 ? names.join(", ") : "No visible hosts") : "Host unavailable"
    output.push(problem)
  }
  return output
}

// The acknowledgement argument mirrors the server-side problem.get filter so a
// payload carried over from the previous configuration stays consistent until
// the refetch lands. "Only acknowledged by me" has no client-side equivalent:
// a published problem records no acknowledging user.
function filterProblems(problems, severities, acknowledgement) {
  var selected = parseSeveritySelection(severities)
  var state = parseAcknowledgement(acknowledgement)
  var allowed = {}
  var output = []
  for (var i = 0; i < selected.length; i++) allowed[selected[i]] = true
  for (var p = 0; p < (problems || []).length; p++) {
    var problem = problems[p]
    if (!problem || !allowed[Number(problem.severity)]) continue
    if (state === "acknowledged" && problem.acknowledged !== true) continue
    if (state === "unacknowledged" && problem.acknowledged === true) continue
    output.push(problem)
  }
  return output
}

function sortProblems(problems) {
  var output = (problems || []).slice()
  output.sort(function(a, b) {
    var severity = Number(b.severity) - Number(a.severity)
    if (severity !== 0) return severity
    var clock = Number(b.clock) - Number(a.clock)
    if (clock !== 0) return clock
    var left = text(a.eventId)
    var right = text(b.eventId)
    if (left === right) return 0
    return left < right ? 1 : -1
  })
  return output
}

function highestSeveritySummary(problems, severities, state) {
  var options = state || {}
  var available = typeof options === "boolean" ? options : options.available !== false
  var truncated = typeof options === "object" && options.truncated === true
  var acknowledgement = typeof options === "object" ? options.acknowledgement : undefined
  if (!available) return { available: false, count: 0, severity: null, definition: null, color: "", truncated: truncated }
  var matching = filterProblems(problems, severities, acknowledgement)
  var highest = -1
  var count = 0
  for (var i = 0; i < matching.length; i++) {
    var value = Number(matching[i].severity)
    if (value > highest) {
      highest = value
      count = 1
    } else if (value === highest) count += 1
  }
  var definition = severityDefinition(highest)
  return {
    available: true,
    count: definition ? count : 0,
    severity: definition ? highest : null,
    definition: definition,
    color: definition ? definition.color : "",
    truncated: truncated
  }
}

function severitySummary(problems, severities, available, truncated, acknowledgement) {
  return highestSeveritySummary(problems, severities, {
    available: available !== false,
    truncated: truncated === true,
    acknowledgement: acknowledgement
  })
}

function formatAge(clock, nowMs) {
  var stamp = Number(clock)
  if (!isFinite(stamp) || stamp <= 0) return "Unknown age"
  var now = Number(nowMs)
  if (!isFinite(now) || now <= 0) now = Date.now()
  var seconds = Math.max(0, Math.floor(now / 1000 - stamp))
  if (seconds < 60) return seconds < 10 ? "just now" : seconds + "s ago"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

function failureBackoffMs(refreshIntervalSec, failureStreak) {
  var base = clampInteger(refreshIntervalSec, DEFAULT_REFRESH_INTERVAL_SEC, MIN_REFRESH_INTERVAL_SEC, MAX_REFRESH_INTERVAL_SEC) * 1000
  var streak = clampInteger(failureStreak, 0, 0, 30)
  var delay = base * Math.pow(2, streak)
  return Math.min(delay, Math.max(base, MAX_BACKOFF_MS))
}

function shouldClaimRefresh(group, nowMs, forced, freshnessMs) {
  var state = group || {}
  var now = Number(nowMs)
  if (!isFinite(now)) now = 0
  if (state.fetching && now - Number(state.startedMs || 0) < CLAIM_TIMEOUT_MS) return false
  if (forced === true) return true
  if (!state.payload) return true
  var freshness = Math.max(0, Number(freshnessMs) || 0)
  return now - Number(state.publishedMs || 0) >= freshness
}

function beginTransaction(published) {
  return {
    published: published || null,
    problemsReady: false,
    hostsReady: false,
    pendingProblems: [],
    pendingHosts: {},
    truncated: false
  }
}

function stageProblems(transaction, result) {
  var tx = transaction
  var source = result || {}
  tx.pendingProblems = (source.problems || []).slice()
  tx.truncated = source.truncated === true
  tx.problemsReady = true
  if (tx.pendingProblems.length === 0) {
    tx.pendingHosts = {}
    tx.hostsReady = true
  }
  return tx
}

function stageHosts(transaction, hostMap) {
  transaction.pendingHosts = hostMap || {}
  transaction.hostsReady = true
  return transaction
}

function canCommitTransaction(transaction) {
  return !!transaction && transaction.problemsReady === true && transaction.hostsReady === true
}

function commitTransaction(transaction, metadata) {
  if (!canCommitTransaction(transaction)) {
    return { ok: false, published: transaction ? transaction.published : null, stale: !!(transaction && transaction.published), error: "Refresh is incomplete" }
  }
  var extra = metadata || {}
  var payload = {
    problems: joinProblemHosts(transaction.pendingProblems, transaction.pendingHosts),
    truncated: transaction.truncated,
    version: trim(extra.version),
    publishedMs: Number(extra.publishedMs) || 0,
    stale: false,
    error: "",
    failureStreak: 0
  }
  return { ok: true, published: payload, stale: false, error: "" }
}

function failTransaction(transaction, error, failureStreak) {
  return {
    ok: false,
    published: transaction ? transaction.published : null,
    stale: !!(transaction && transaction.published),
    error: safeMessage(error),
    failureStreak: clampInteger(failureStreak, 1, 1, 30)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULT_TOKEN_FILE: DEFAULT_TOKEN_FILE,
    DEFAULT_REFRESH_INTERVAL_SEC: DEFAULT_REFRESH_INTERVAL_SEC,
    MIN_REFRESH_INTERVAL_SEC: MIN_REFRESH_INTERVAL_SEC,
    MAX_REFRESH_INTERVAL_SEC: MAX_REFRESH_INTERVAL_SEC,
    DEFAULT_PROBLEM_LIMIT: DEFAULT_PROBLEM_LIMIT,
    MIN_PROBLEM_LIMIT: MIN_PROBLEM_LIMIT,
    MAX_PROBLEM_LIMIT: MAX_PROBLEM_LIMIT,
    DEFAULT_CONNECT_TIMEOUT_SEC: DEFAULT_CONNECT_TIMEOUT_SEC,
    DEFAULT_TOTAL_TIMEOUT_SEC: DEFAULT_TOTAL_TIMEOUT_SEC,
    MAX_BACKOFF_MS: MAX_BACKOFF_MS,
    CLAIM_TIMEOUT_MS: CLAIM_TIMEOUT_MS,
    CURL_STATUS_MARKER: CURL_STATUS_MARKER,
    FETCH_SCRIPT: FETCH_SCRIPT,
    PROBLEM_OUTPUT: PROBLEM_OUTPUT,
    SEVERITIES: SEVERITIES,
    ACKNOWLEDGEMENTS: ACKNOWLEDGEMENTS,
    ACK_ACTION_ACKNOWLEDGE: ACK_ACTION_ACKNOWLEDGE,
    trim: trim,
    clampInteger: clampInteger,
    expandHome: expandHome,
    firstNonEmptyLine: firstNonEmptyLine,
    firstTokenLine: firstNonEmptyLine,
    endpointError: endpointError,
    normalizeEndpoint: normalizeEndpoint,
    isHttpsEndpoint: isHttpsEndpoint,
    normalizeSettings: normalizeSettings,
    parseSeveritySelection: parseSeveritySelection,
    parseSeverities: parseSeveritySelection,
    persistSeveritySelection: persistSeveritySelection,
    toggleSeverity: toggleSeverity,
    severityDefinition: severityDefinition,
    severityByValue: severityDefinition,
    severityValues: severityValues,
    parseAcknowledgement: parseAcknowledgement,
    persistAcknowledgement: persistAcknowledgement,
    acknowledgementDefinition: acknowledgementDefinition,
    sha256: sha256,
    tokenDigest: sha256,
    configurationSignature: configurationSignature,
    configSignature: configurationSignature,
    dataSourceSignature: dataSourceSignature,
    parseVersion: parseVersion,
    compareVersions: compareVersions,
    isSupportedVersion: isSupportedVersion,
    curlConfigEscape: curlConfigEscape,
    curlEscape: curlConfigEscape,
    curlArgv: curlArgv,
    buildCurlEnvironment: buildCurlEnvironment,
    buildApiInfoVersionRequest: buildApiInfoVersionRequest,
    buildProblemGetRequest: buildProblemGetRequest,
    buildTriggerGetRequest: buildTriggerGetRequest,
    buildUserCheckAuthenticationRequest: buildUserCheckAuthenticationRequest,
    requestBody: requestBody,
    safeMessage: safeMessage,
    parseCurlOutput: parseCurlOutput,
    classifyHttpStatus: classifyHttpStatus,
    classifyCurlResult: classifyCurlResult,
    classifyJsonRpcError: classifyJsonRpcError,
    parseJsonRpcResponse: parseJsonRpcResponse,
    parseVersionResponse: parseVersionResponse,
    parseIdentityResponse: parseIdentityResponse,
    normalizeTags: normalizeTags,
    normalizeProblem: normalizeProblem,
    normalizeProblemResult: normalizeProblemResult,
    truncateProblems: normalizeProblemResult,
    uniqueIds: uniqueIds,
    normalizeHosts: normalizeHosts,
    joinProblemHosts: joinProblemHosts,
    filterProblems: filterProblems,
    sortProblems: sortProblems,
    highestSeveritySummary: highestSeveritySummary,
    highestSummary: highestSeveritySummary,
    severitySummary: severitySummary,
    formatAge: formatAge,
    failureBackoffMs: failureBackoffMs,
    backoffMs: failureBackoffMs,
    shouldClaimRefresh: shouldClaimRefresh,
    beginTransaction: beginTransaction,
    stageProblems: stageProblems,
    stageHosts: stageHosts,
    canCommitTransaction: canCommitTransaction,
    commitTransaction: commitTransaction,
    failTransaction: failTransaction
  }
}
