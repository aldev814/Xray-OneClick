#!/usr/bin/env bash
# Focused offline checks; no network, services, or installed Xray required.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/00-bootstrap.sh"
TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/xray-config-repairs.XXXXXX")"
trap 'rm -rf "$TASK_TMP"' EXIT
fail() { echo "[FAIL] $*" >&2; exit 1; }

test_migration_preserves_inbounds() (
    CONFIG_DIR="$TASK_TMP/migration"
    CONFIG_FILE="$CONFIG_DIR/config.json"
    STATE_FILE="$CONFIG_DIR/state.json"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' '{"inbounds":[{"tag":"broken-reality","streamSettings":{"security":"reality","realitySettings":{}}},{"tag":"keep-me"}]}' >"$CONFIG_FILE"
    cp "$CONFIG_FILE" "$CONFIG_DIR/before.json"
    if normalize_config_schema false >/dev/null 2>&1; then
        fail "missing REALITY target must fail instead of removing the inbound"
    fi
    cmp -s "$CONFIG_FILE" "$CONFIG_DIR/before.json" || fail "failed migration modified config"
    if normalize_config_schema true >/dev/null 2>&1; then
        fail "dry-run must also detect missing REALITY target"
    fi
    echo '[OK] invalid REALITY target preserves all inbounds'
)

test_migration_validation_rollback() (
    CONFIG_DIR="$TASK_TMP/rollback"
    CONFIG_FILE="$CONFIG_DIR/config.json"
    STATE_FILE="$CONFIG_DIR/state.json"
    BIN_PATH="$CONFIG_DIR/xray"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' '{"inbounds":[{"tag":"vless+tcp+reality","protocol":"vless","sniffing":{"enabled":true},"streamSettings":{"security":"reality","realitySettings":{"dest":"example.com:443"}}}]}' >"$CONFIG_FILE"
    printf '%s\n' '{"original":true}' >"$STATE_FILE"
    cp "$CONFIG_FILE" "$CONFIG_DIR/before-config.json"
    cp "$STATE_FILE" "$CONFIG_DIR/before-state.json"
    printf '#!/bin/sh\nexit 23\n' >"$BIN_PATH"
    chmod +x "$BIN_PATH"
    migrate_old_state() { printf '%s\n' '{"partial":true}' >"$STATE_FILE"; }
    run_migrate_command >/dev/null 2>&1 && fail "rejected config must fail migration"
    cmp -s "$CONFIG_FILE" "$CONFIG_DIR/before-config.json" || fail "config not restored"
    cmp -s "$STATE_FILE" "$CONFIG_DIR/before-state.json" || fail "state not restored"
    echo '[OK] Xray validation failure rolls back config and state'
)

test_export_endpoints() (
    CONFIG_DIR="$TASK_TMP/export"
    CONFIG_FILE="$CONFIG_DIR/config.json"
    STATE_FILE="$CONFIG_DIR/state.json"
    ASSET_DIR="$CONFIG_DIR/assets"
    mkdir -p "$CONFIG_DIR"
    cat >"$CONFIG_FILE" <<'JSON'
{"inbounds":[
  {"tag":"ss2022-in","listen":"0.0.0.0","port":9000,"settings":{"method":"2022-blake3-aes-128-gcm","password":"test-password"}},
  {"tag":"socks-in","listen":"::","port":1080,"settings":{"users":[{"user":"user@name","pass":"p:a#ss"}]}},
  {"tag":"vless-enc-xhttp-in","listen":"::","port":8443},
  {"tag":"hysteria2-in","listen":"::","port":8444}
]}
JSON
    cat >"$STATE_FILE" <<'JSON'
{"ss2022":{"listen_scope":"ipv4"},
 "vless_enc_xhttp":{"port":8443,"uuid":"test-uuid","path":"/api/test","encryption":"test-encryption"},
 "hysteria2":{"port":8444,"auth":"test-auth","sni":"example.com","obfs":"test-obfs"}}
JSON
    get_public_addresses() { PUBLIC_IPV4=203.0.113.10; PUBLIC_IPV6=2001:db8::10; }
    get_local_addresses() { fail 'export must not use private interface addresses'; }
    # Simulate leftovers from another protocol installed in the same menu.
    ENC_XHTTP_PORT=9999
    VLESS_UUID=wrong-uuid
    HY2_PORT=9998
    local links
    links="$(render_export_links dual)" || fail 'dual export failed'
    [[ "$(printf '%s\n' "$links" | wc -l | tr -d ' ')" == 8 ]] || fail 'dual must export both families for all four protocols'
    [[ "$links" == *'@203.0.113.10:8443'* && "$links" == *'@[2001:db8::10]:8443'* ]] || fail 'XHTTP endpoint families missing'
    [[ "$links" == *'user%40name:p%3Aa%23ss@'* ]] || fail 'SOCKS credentials not URI encoded'
    [[ "$links" != *wrong-uuid* && "$links" != *:9999* && "$links" != *:9998* ]] || fail 'menu globals contaminated exported links'
    links="$(render_export_links ipv6)" || fail 'IPv6 export failed'
    [[ "$links" != *203.0.113.10* && "$(printf '%s\n' "$links" | wc -l | tr -d ' ')" == 4 ]] || fail 'IPv6 export includes the wrong family'
    jq '.inbounds[0].streamSettings.sockopt.V6Only=true' "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    [[ "$(config_inbound_listen_scope "$SS_TAG")" == ipv6 ]] || fail 'v6only listener misidentified'
    links="$(render_export_links ipv4)" || fail 'IPv4 export failed'
    if printf '%s\n' "$links" | grep -q '^ss://'; then
        fail 'IPv6-only listener exported as IPv4'
    fi
    jq '.endpoint.custom="relay.example:23456"' "$STATE_FILE" >"$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    links="$(render_export_links dual)" || fail 'custom endpoint export failed'
    [[ "$(printf '%s\n' "$links" | wc -l | tr -d ' ')" == 4 ]] || fail 'custom endpoint emitted duplicate links'
    [[ "$(printf '%s\n' "$links" | grep -cF '@relay.example:23456')" == 4 ]] || fail 'custom host/port ignored by a protocol'
    # An external IPv6 relay can forward to a local IPv4 listener.
    get_public_addresses() { PUBLIC_IPV4=203.0.113.10; PUBLIC_IPV6=""; }
    links="$(render_export_links ipv6)" || fail 'custom endpoint should work without a local IPv6 address'
    [[ "$links" != *YOUR_SERVER* ]] || fail 'placeholder endpoint exported'
    jq '.inbounds[1].settings |= (.accounts=.users | del(.users))' "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    links="$(render_export_links ipv6)" || fail 'legacy accounts export failed'
    [[ "$links" == *'user%40name:p%3Aa%23ss@'* ]] || fail 'legacy SOCKS credentials lost'
    jq 'del(.endpoint.custom)' "$STATE_FILE" >"$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    # Saved links must not bypass the requested address family or missing state.
    jq '.hysteria2={link:"hysteria2://stale@old.example:9999"}' "$STATE_FILE" >"$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    links="$(render_export_links ipv4)" || fail 'remaining protocols should still export'
    [[ "$links" != *old.example* ]] || fail 'stale cached link leaked into export'
    echo '[OK] public/custom endpoints, dual export, URI credentials and menu isolation'
)

test_documented_schema_migration() (
    CONFIG_DIR="$TASK_TMP/schema"
    CONFIG_FILE="$CONFIG_DIR/config.json"
    STATE_FILE="$CONFIG_DIR/state.json"
    mkdir -p "$CONFIG_DIR"
    cat >"$CONFIG_FILE" <<'JSON'
{"inbounds":[
 {"tag":"vless+tcp+reality","protocol":"vless","settings":{"clients":[{"id":"keep-id","flow":"xtls-rprx-vision"}]},"streamSettings":{"security":"reality","realitySettings":{"dest":"127.0.0.1:40000","spiderX":"/client-only"}}},
 {"tag":"reality-defender","protocol":"dokodemo-door","settings":{"address":"example.com","port":443,"network":"tcp"}},
 {"tag":"socks-in","protocol":"socks","settings":{"accounts":[{"user":"keep-user","pass":"keep-pass"}]}},
 {"tag":"hysteria2-in","protocol":"hysteria","settings":{"clients":[{"auth":"keep-auth"}]}},
 {"tag":"tunnel-test","protocol":"tunnel","port":"30000,30001","settings":{"address":"example.com","port":443,"network":"tcp,udp","portMap":{"30001":"[2001:db8::1]:8443"}}},
 {"tag":"fragment-test","streamSettings":{"finalmask":{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","length":"100-200","delay":"10-20","maxSplit":"3-6"}}]}}}
]}
JSON
    cp "$CONFIG_FILE" "$CONFIG_DIR/original.json"
    normalize_config_schema true >/dev/null || fail 'schema dry-run failed'
    cmp -s "$CONFIG_FILE" "$CONFIG_DIR/original.json" || fail 'schema dry-run wrote config'
    normalize_config_schema false >/dev/null || fail 'schema migration failed'
    jq -e '
      (.inbounds | length == 6) and
      .inbounds[0].settings.users == [{id:"keep-id",flow:"xtls-rprx-vision"}] and
      (.inbounds[0].settings | has("clients") | not) and
      (.inbounds[0].streamSettings.realitySettings | .target == "127.0.0.1:40000" and (has("spiderX") | not)) and
      .inbounds[1].settings == {rewriteAddress:"example.com",rewritePort:443,allowedNetwork:"tcp"} and
      .inbounds[2].settings.users == [{user:"keep-user",pass:"keep-pass"}] and
      .inbounds[3].settings.users == [{auth:"keep-auth"}] and
      .inbounds[4].settings.portMap == {"30001":"[2001:db8::1]:8443"} and
      .inbounds[4].settings.allowedNetwork == "tcp,udp" and
      .inbounds[5].streamSettings.finalmask.tcp[0].settings == {packets:"tlshello",lengths:["100-200"],delays:["10-20"],maxSplit:"3-6"}
    ' "$CONFIG_FILE" >/dev/null || fail 'schema migration lost user, tunnel or fragment parameters'
    cp "$CONFIG_FILE" "$CONFIG_DIR/once.json"
    normalize_config_schema false >/dev/null || fail 'repeat schema migration failed'
    cmp -s "$CONFIG_FILE" "$CONFIG_DIR/once.json" || fail 'schema migration is not idempotent'
    printf '%s\n' '{"profile":{"spider_x":"/keep-client-path","finalmask_json":{"tcp":[{"type":"fragment","settings":{"length":"100-200","delay":"10-20"}}]}}}' >"$STATE_FILE"
    migrate_finalmask_state false || fail 'FinalMask state migration failed'
    jq -e '.profile.spider_x == "/keep-client-path" and .profile.finalmask_json.tcp[0].settings.lengths == ["100-200"]' "$STATE_FILE" >/dev/null || fail 'state migration lost client spider path or fragment params'
    jq '.inbounds[0].settings.clients=[{id:"conflicting-id"}]' "$CONFIG_FILE" >"$CONFIG_FILE.tmp"
    mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    cp "$CONFIG_FILE" "$CONFIG_DIR/conflict.json"
    normalize_config_schema false >/dev/null 2>&1 && fail 'conflicting users must not be silently discarded'
    cmp -s "$CONFIG_FILE" "$CONFIG_DIR/conflict.json" || fail 'conflicting migration modified config'
    echo '[OK] schema migration preserves users, port maps, client paths and state'
)

test_finalmask_documented_arrays() (
    local json encoded
    json="$(build_finalmask_custom_json tlshello 100-200 0 0)" || fail 'zero delay/maxSplit should be allowed'
    validate_finalmask_json "$json" || fail 'documented fragment arrays rejected'
    jq -e '.tcp[0].settings | .lengths == ["100-200"] and .delays == ["0"] and .maxSplit == "0" and (has("length") or has("delay") | not)' <<<"$json" >/dev/null || fail 'generator did not use documented arrays'
    validate_finalmask_json '{"tcp":[{"type":"fragment","settings":{"lengths":["3-5","6-8","10-20"],"delays":["0","10-20"],"maxSplit":0}}]}' || fail 'multiple fragment ranges rejected'
    validate_finalmask_json '{"tcp":[{"type":"fragment","settings":{"lengths":["0"],"delays":["0"]}}]}' && fail 'zero final length permits an infinite loop'
    encoded="$(encode_finalmask_for_share_link '{"tcp":[{"type":"fragment","settings":{"length":"100-200","delay":"10-20"}}]}')" || fail 'legacy fragment share normalization failed'
    [[ "$encoded" == *lengths* && "$encoded" == *delays* ]] || fail 'share link retained old fragment fields'
    echo '[OK] documented FinalMask arrays, validation and legacy sharing'
)

test_migration_preserves_inbounds
test_migration_validation_rollback
test_export_endpoints
test_documented_schema_migration
test_finalmask_documented_arrays
