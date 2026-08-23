# Zabbix Problems for Omarchy

`dechnik.zabbix` is an Omarchy Quattro bar widget for unresolved Zabbix
trigger problems. It keeps the most severe visible state in the bar and opens a
read-only, severity-filterable problem list with host names, age,
acknowledgment, and suppression state.

## Bar Summary

The bar number is deliberately **not the total problem count**. From the
retrieved problems that match the selected severity filter, the plugin finds
the highest numeric severity and counts only problems at exactly that
severity. Lower-severity problems are not added.

For example, one Disaster, three High, and seven Warning problems produce a red
Disaster icon and `1`, not `11`. Four High problems with nothing at Disaster
produce a High icon and `4`. A successful result with no matching problems
shows a neutral `0`; no successful result yet shows a neutral `?` instead of a
false healthy zero. A truncated result can make the displayed count incomplete.

## Requirements

- Omarchy Quattro with third-party shell plugin support
- `curl`
- One Zabbix 7.0 or newer frontend/API endpoint reachable over HTTPS
- A Zabbix API token with the read access described below

The configured URL may be the frontend root, such as
`https://zabbix.example.com/zabbix`, or the full
`https://zabbix.example.com/zabbix/api_jsonrpc.php` URL. HTTP URLs, embedded
credentials, queries, and fragments are rejected.

## Install

Install the Git repository and enable its bar widget in one step:

```bash
omarchy plugin add https://github.com/dechnik/omarchy-zabbix.git --enable
```

Or install first and enable later in the default right section:

```bash
omarchy plugin add https://github.com/dechnik/omarchy-zabbix.git
omarchy plugin enable dechnik.zabbix --section right
```

Move it later if desired:

```bash
omarchy bar move dechnik.zabbix --section right
```

Omarchy warns before installing because third-party plugins execute
unsandboxed inside `omarchy-shell`. Review repositories before enabling them.

## Zabbix Access

Create the token for a dedicated, read-only Zabbix user where practical. An API
token inherits its owner's user type, role, user-group permissions, and host
visibility; the token does not have an independent permission set.

The minimum role/API setup is:

- Enable **Access to API** for the token owner's role.
- Permit `problem.get` and `trigger.get`. If the role uses an API-method Allow
  list, add both exact methods. If it uses a Deny list, do not deny them.
- `apiinfo.version` is only available to unauthenticated callers. The plugin
  calls it without the token before its first authenticated request, so it is
  not a permission that can or needs to be granted to the token's role.
- Any Zabbix user type can call `problem.get` and `trigger.get` unless its role
  revokes those methods. No create, update, acknowledge, suppress, or close
  method is needed.
- Give the token owner's user groups at least read visibility to the host
  groups whose problems should be shown.

Zabbix applies normal object visibility to API results. The plugin therefore
shows only problems and trigger/host context visible to the token owner; it
cannot distinguish an invisible object from one that does not exist. A problem
whose trigger enrichment is absent remains listed as `Hosts unavailable`.
Denial of the entire `trigger.get` method fails the transactional refresh
instead of publishing problems with a knowingly incomplete enrichment result.

## Token File

The default token path is `~/.config/omarchy/zabbix/token`. Create it without
putting the token in command history or process arguments:

```bash
install -d -m 700 ~/.config/omarchy/zabbix
umask 077
read -rsp 'Zabbix API token: ' ZABBIX_TOKEN; printf '\n'
printf '%s\n' "$ZABBIX_TOKEN" > ~/.config/omarchy/zabbix/token
unset ZABBIX_TOKEN
chmod 600 ~/.config/omarchy/zabbix/token
```

The plugin trims whitespace, skips blank lines, and uses the **first non-empty
line**. Later lines are ignored. The file is watched, so replacing or editing
it reloads the token without restarting the shell. Keep it owned by your user
and at mode `0600`; the plugin relies on this setup and does not enforce the
mode itself.

## Configure

Set the HTTPS frontend/API URL after enabling the widget:

```bash
omarchy bar set dechnik.zabbix url 'https://zabbix.example.com/zabbix'
```

Settings can be changed in the widget settings or with
`omarchy bar set dechnik.zabbix <key> <value>`. The plugin normalizes numeric
and boolean strings written by this command. For severities, use a comma-separated
CLI value; the settings UI may store the equivalent array. Non-secret settings
are persisted in the widget entry in `~/.config/omarchy/shell.json` and hot-reload.

| Key | Default | Allowed values and behavior |
|---|---|---|
| `url` | `""` | HTTPS frontend root or full `api_jsonrpc.php` URL. Required. |
| `tokenFile` | `"~/.config/omarchy/zabbix/token"` | Path whose first non-empty line is the token. `~` and `~/` are expanded. |
| `caCertificateFile` | `""` | Optional path to a PEM CA certificate/trust anchor for a private CA or self-signed server. |
| `insecureTls` | `false` | `true` explicitly disables certificate and hostname verification. |
| `refreshIntervalSec` | `60` | Integer from `15` to `3600`; settings UI step `15`. |
| `problemLimit` | `100` | Integer from `1` to `1000`; settings UI step `25`. |
| `severities` | `["0", "1", "2", "3", "4", "5"]` | One or more of `0` Not classified, `1` Information, `2` Warning, `3` Average, `4` High, `5` Disaster. The panel will not remove the final selected severity. |

Examples:

```bash
omarchy bar set dechnik.zabbix refreshIntervalSec 120
omarchy bar set dechnik.zabbix problemLimit 250
omarchy bar set dechnik.zabbix severities 4,5
omarchy bar set dechnik.zabbix tokenFile '~/.config/omarchy/zabbix/token'
```

Values outside numeric ranges are clamped by the runtime. Invalid or empty
severity selections normalize to all six severities.

## TLS

Certificate and hostname verification are enabled by default.

For a certificate issued by the system trust store, no additional setting is
needed. For a private CA or a self-signed server, store the issuing CA PEM (or
the self-signed server certificate used as its own trust anchor) locally and
configure it:

```bash
omarchy bar set dechnik.zabbix caCertificateFile '~/.config/omarchy/zabbix/private-ca.pem'
```

The certificate still has to match the hostname in `url`. Prefer this mode to
disabling verification.

Insecure mode is an explicit last resort:

```bash
omarchy bar set dechnik.zabbix insecureTls true
```

This is equivalent to accepting any server certificate and disables hostname
verification. A man-in-the-middle can impersonate Zabbix and intercept the API
token and monitoring data. The panel and status output remain visibly marked
as insecure while this setting is active. Turn it off after diagnosis:

```bash
omarchy bar set dechnik.zabbix insecureTls false
```

## Bar And Panel

| Input | Action |
|---|---|
| Left click the bar widget | Toggle the problem panel. |
| Right click the bar widget | Request an immediate refresh without opening the panel. |
| Hover the bar widget | Show the highest-severity summary and loading, stale, truncation, or insecure-TLS state. |
| Click the panel refresh button | Request an immediate refresh. |
| Click a severity | Include or exclude it; the final selected severity cannot be removed. |
| Click a problem row | Move the panel cursor to that read-only row. |

The list is sorted by severity descending, then newest first. Severity changes
are persisted, immediately filter the last published result, and trigger a new
server-filtered request. The panel shows all visible hosts returned by Zabbix
and marks acknowledged and suppressed problems; it never changes Zabbix state.

### Keyboard

| Key | Action |
|---|---|
| `Up` / `Down` or `j` / `k` | Move through the six severity controls and problem rows. |
| `Enter` | Toggle the focused severity. Problem rows have no activation action. |
| `r` | Request an immediate refresh. |
| `Esc` | Close the panel. |
| `Tab` / `Shift+Tab` | Switch to the next/previous panel in the same bar section and monitor. |

## IPC

The widget exposes these exact direct IPC methods:

```bash
omarchy-shell dechnik.zabbix open
omarchy-shell dechnik.zabbix close
omarchy-shell dechnik.zabbix show
omarchy-shell dechnik.zabbix hide
omarchy-shell dechnik.zabbix toggle
omarchy-shell dechnik.zabbix refresh
omarchy-shell dechnik.zabbix status
```

`show` is an alias of `open`; `hide` is an alias of `close`; `refresh` returns
`ok`. `status` returns a sanitized one-line state such as
`zabbix severity=high count=3 version=7.0.0 age=12s` and may add `stale`,
`refreshing`, `truncated`, or `insecure-tls`. It does not include the endpoint,
token, problem names, or host names.

On a multi-monitor bar, use the shell router for a panel-toggle hotkey:

```bash
omarchy-shell shell toggle dechnik.zabbix
```

This shell-level form chooses the already-open copy first, otherwise the copy
on Hyprland's focused monitor. A direct `dechnik.zabbix toggle` targets the
per-monitor IPC handler that registered that target and is not the reliable
focused-monitor route. Direct `refresh` and `status` are still suitable because
equal configurations share polling state and published data across monitors.

## Limits And Refresh Behavior

- Each `problem.get` asks for `problemLimit + 1` newest matching unresolved
  trigger problems. The extra row detects truncation and is discarded; at most
  `problemLimit` valid problems are displayed.
- When the extra row exists, the panel warns that more matching problems may
  exist and IPC status includes `truncated`. Counts and filters then describe
  only the retained result, never a server-wide total.
- The first configured load is immediate. Later successful polling uses
  `refreshIntervalSec`. Equivalent monitor instances coordinate one polling
  sequence per effective configuration rather than polling once per monitor.
- A refresh is atomic: version checking, `problem.get`, and, when needed,
  batched `trigger.get` host enrichment must complete before replacing the
  published result. During refresh, the last complete result stays visible.
- After a failed refresh, a previous complete result stays visible and is
  marked stale with the current error. A first failure has no data and appears
  unavailable, not as zero. A later complete success clears stale/error state
  and resets backoff.
- Consecutive failures double the interval after each failure, starting at
  twice the configured interval and capped at the greater of 15 minutes or the
  configured interval. Manual refresh and opening a stale/no-data panel may
  retry immediately, but never start concurrent equivalent work.
- Curl uses a 5-second connection timeout and 12-second total timeout; a
  20-second QML watchdog is the final bound. A missing token file is retried
  every 5 seconds.

## Security Model

- The token is never written to `shell.json`, process arguments, IPC status,
  plugin logs, or user-visible errors. Error text is sanitized and bounded.
- Authenticated requests pass the token to a short-lived Bash process through
  `ZABBIX_TOKEN`; Bash feeds the Bearer header to curl through curl config on
  standard input. `/proc/<pid>/cmdline` therefore does not contain the token.
- The token does exist in the mode-`0600` file, in `omarchy-shell` QML memory,
  in the child process environment while a request runs, and briefly in Bash
  and curl memory. Environment variables are not a secret from root or from
  processes allowed to inspect this user's `/proc/<pid>/environ`.
- Omarchy plugins are unsandboxed code in the same long-lived shell process.
  The trust boundary includes your user account, root, `omarchy-shell`, every
  enabled shell plugin, and programs with same-user process-inspection access.
  File mode `0600` protects against other ordinary local users; it does not
  protect against that trust boundary.

Use a dedicated least-privilege token, review enabled plugins, keep TLS
verification on, and revoke/rotate the token if the account or machine may be
compromised.

## Troubleshooting

Start with:

```bash
command -v curl
omarchy plugin list
omarchy-shell dechnik.zabbix status
```

- **Setup or endpoint:** `setup-required`, `endpoint`, or a URL message means
  `url` is empty/invalid, is not HTTPS, contains credentials/query/fragment, or
  points somewhere other than the frontend root or `api_jsonrpc.php`.
- **Token file or authentication:** Confirm the configured path, owner, mode
  `0600`, and first non-empty line. Rotate an expired/revoked token. The watched
  file normally reloads automatically.
- **Permission or unexpectedly empty results:** Enable role API access and
  allow `problem.get` plus `trigger.get`. Then check the token owner's user
  groups and read access to the relevant host groups. Zabbix silently scopes
  results to visible objects.
- **TLS:** For an unknown private issuer, configure `caCertificateFile`; for a
  hostname mismatch, fix the URL or certificate. Use `insecureTls` only as a
  temporary diagnostic because it exposes the token to interception.
- **Network, DNS, timeout, or HTTP:** Check name resolution, routing, firewall,
  reverse proxy, and the final API URL. Redirects are rejected; configure the
  final HTTPS URL directly.
- **Version or response/API error:** Zabbix older than 7.0 is unsupported.
  Proxies and login pages returning HTML cause a malformed-response error.
  Unknown JSON-RPC errors are shown in sanitized form.
- **Stale or truncated:** Stale means the displayed complete result predates a
  failed refresh. Truncated means `problemLimit` was exceeded. Refresh after
  fixing the error or raise the limit with awareness of larger API responses.
- **Widget or hot-reload issue:** Confirm `dechnik.zabbix` is enabled. Saved
  plugin files normally hot-reload; during development, a full
  `omarchy restart shell` is the reliable reset for stale monitor instances or
  IPC registrations.

## Remove

```bash
omarchy plugin disable dechnik.zabbix
omarchy plugin remove dechnik.zabbix
```

Removal unloads the plugin and its widget settings but intentionally does not
delete the token, a custom CA file, or the server-side Zabbix token. Revoke the
API token in Zabbix, then remove local credentials if they are no longer used:

```bash
rm ~/.config/omarchy/zabbix/token
rmdir ~/.config/omarchy/zabbix
```

Adjust those paths if `tokenFile` or `caCertificateFile` was customized.

## Development

From the repository root:

```bash
node test/model.test.js
omarchy plugin validate .
```

The Node suite exercises the pure request, parsing, security, filtering,
summary, transaction, and backoff model. Validation checks the plugin manifest
and entry point. Neither command contacts a live Zabbix server or constitutes
live production, trusted-TLS, custom-CA, insecure-TLS, or multi-monitor
verification; no such test is claimed here.

## License

MIT. See [LICENSE](LICENSE).
