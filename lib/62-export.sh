#!/usr/bin/env bash
# ike export command implementations.

render_export_report() {
    render_export_report_body | redact_sensitive_stream
}

render_export_report_body() {
    local tags ports xray_version

    [[ -n "${INIT_SYSTEM:-}" ]] || check_os
    echo "Xray-OneClick 脱敏诊断报告"
    echo "----------------------------------------"
    echo "SCRIPT_VERSION: ${SCRIPT_VERSION}"
    if [[ -x "$BIN_PATH" ]]; then
        xray_version="$("$BIN_PATH" version 2>/dev/null | head -n 1 || true)"
        echo "xray version: ${xray_version:-读取失败}"
    else
        echo "xray version: 未安装"
    fi
    echo "service status: $(xray_service_status)"
    echo "config test: $(xray_config_test_status)"
    echo "installed protocols: $(installed_protocols_summary)"
    if [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
        tags="$(jq -r '[.inbounds[]?.tag] | join(", ")' "$CONFIG_FILE" 2>/dev/null)"
        ports="$(jq -r '[.inbounds[]? | select(.port != null) | (.tag + ":" + (.port|tostring))] | join(", ")' "$CONFIG_FILE" 2>/dev/null)"
        echo "inbound tags: ${tags:-无}"
        echo "listen ports: ${ports:-无}"
    fi
    echo
    echo "Reality 摘要:"
    if inbound_exists "$REALITY_TAG"; then
        jq -r --arg tag "$REALITY_TAG" '.inbounds[]? | select(.tag == $tag) | "  port=\(.port) sni=\(.streamSettings.realitySettings.serverNames[0] // "") flow=\((.settings.users // .settings.clients)[0].flow // "")"' "$CONFIG_FILE"
        jq -r ".${REALITY_STATE_KEY} // {} | \"  publicKey=\(.public_key // \"\") shortId=\(.default_short_id // \"\") link=\(.link // \"\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  未安装"
    fi
    echo
    echo "XHTTP-FinalMask 摘要:"
    if inbound_exists "$VLESS_XHTTP_FM_TAG"; then
        jq -r --arg tag "$VLESS_XHTTP_FM_TAG" '.inbounds[]? | select(.tag == $tag) | "  port=\(.port) path=\(.streamSettings.xhttpSettings.path // "") finalmask=\(.streamSettings | has("finalmask"))"' "$CONFIG_FILE"
        jq -r ".${VLESS_XHTTP_FM_STATE_KEY} // {} | \"  finalmask_enabled=\(.finalmask_enabled // false) mode=\(.finalmask_mode // \"off\") preset=\(.finalmask_preset // \"none\") summary=\(.finalmask_summary // \"\") link=\(.link // \"\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  未安装"
    fi
    echo
    echo "ENC-FinalMask (sudoku) 摘要:"
    if inbound_exists "$VLESS_ENC_FM_TAG"; then
        jq -r --arg tag "$VLESS_ENC_FM_TAG" '.inbounds[]? | select(.tag == $tag) | "  port=\(.port) network=\(.streamSettings.network) finalmask=\(.streamSettings.finalmask.tcp[0].type // "")"' "$CONFIG_FILE"
        jq -r ".${VLESS_ENC_FM_STATE_KEY} // {} | \"  auth=\(.auth // \"\") link=\(.link // \"\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  未安装"
    fi
    echo
    echo "ENC-XHTTP 摘要:"
    if inbound_exists "$VLESS_ENC_XHTTP_TAG"; then
        jq -r --arg tag "$VLESS_ENC_XHTTP_TAG" '.inbounds[]? | select(.tag == $tag) | "  port=\(.port) network=\(.streamSettings.network) path=\(.streamSettings.xhttpSettings.path // "")"' "$CONFIG_FILE"
        jq -r ".${VLESS_ENC_XHTTP_STATE_KEY} // {} | \"  auth=\(.auth // \"\") link=\(.link // \"\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  未安装"
    fi
    echo
    echo "Hysteria2 摘要:"
    if inbound_exists "$HY2_TAG"; then
        jq -r --arg tag "$HY2_TAG" '.inbounds[]? | select(.tag == $tag) | "  port=\(.port) protocol=\(.protocol) obfs=\(.streamSettings.finalmask.udp[0].type // "")"' "$CONFIG_FILE"
        jq -r ".${HY2_STATE_KEY} // {} | \"  sni=\(.sni // \"\") pinnedPeerCertSha256=\(.pinnedPeerCertSha256 // \"\") link=\(.link // \"\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  未安装"
    fi
    echo
    echo "高级协议组合摘要:"
    if inbound_exists "$VLESS_XHTTP_REALITY_TAG"; then
        jq -r --arg tag "$VLESS_XHTTP_REALITY_TAG" '.inbounds[]? | select(.tag == $tag) | "  XHTTP-Reality port=\(.port) path=\(.streamSettings.xhttpSettings.path // "") sni=\(.streamSettings.realitySettings.serverNames[0] // "") flow=\((.settings.users // .settings.clients)[0].flow // "none")"' "$CONFIG_FILE"
        jq -r ".${VLESS_XHTTP_REALITY_STATE_KEY} // {} | \"    publicKey=\(.public_key // \"\") shortId=\(.default_short_id // \"\") flow=\(.flow // \"none\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  XHTTP-Reality: 未安装"
    fi
    if inbound_exists "$VLESS_ENC_REALITY_TAG"; then
        jq -r --arg tag "$VLESS_ENC_REALITY_TAG" '.inbounds[]? | select(.tag == $tag) | "  Enc-Reality port=\(.port) sni=\(.streamSettings.realitySettings.serverNames[0] // "") flow=\((.settings.users // .settings.clients)[0].flow // "none")"' "$CONFIG_FILE"
        jq -r ".${VLESS_ENC_REALITY_STATE_KEY} // {} | \"    publicKey=\(.public_key // \"\") shortId=\(.default_short_id // \"\") flow=\(.flow // \"none\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  Enc-Reality: 未安装"
    fi
    if inbound_exists "$VLESS_FULLSTACK_TAG"; then
        jq -r --arg tag "$VLESS_FULLSTACK_TAG" '.inbounds[]? | select(.tag == $tag) | "  FullStack port=\(.port) path=\(.streamSettings.xhttpSettings.path // "") sni=\(.streamSettings.realitySettings.serverNames[0] // "") flow=\((.settings.users // .settings.clients)[0].flow // "none") finalmask=\(.streamSettings | has("finalmask"))"' "$CONFIG_FILE"
        jq -r ".${VLESS_FULLSTACK_STATE_KEY} // {} | \"    publicKey=\(.public_key // \"\") shortId=\(.default_short_id // \"\") flow=\(.flow // \"none\") finalmask_enabled=\(.finalmask_enabled // false) mode=\(.finalmask_mode // \"off\") preset=\(.finalmask_preset // \"none\") summary=\(.finalmask_summary // \"\")\"" "$STATE_FILE" 2>/dev/null
    else
        echo "  FullStack: 未安装"
    fi
    echo
    echo "最近日志摘要:"
    if [[ "${INIT_SYSTEM:-}" == "openrc" ]]; then
        tail_xray_service_logs 20 || echo "  OpenRC 日志文件尚未生成"
    elif command -v journalctl >/dev/null 2>&1; then
        journalctl -u "$SERVICE_NAME" -n 20 --no-pager 2>/dev/null | redact_sensitive_stream || true
    else
        echo "  journalctl 不可用"
    fi
    echo
    echo "脱敏 config 摘要:"
    redact_config_json || true
}

render_export_clients() {
    echo "Xray-OneClick 客户端参数导出"
    echo "----------------------------------------"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "未找到 config.json"
        return 0
    fi
    init_state || return 1
    view_config dual quick || true
    if [[ -f "$STATE_FILE" ]] && jq -e ".${VLESS_XHTTP_FM_STATE_KEY}.finalmask_enabled == true" "$STATE_FILE" >/dev/null 2>&1; then
        echo
        echo "提示: 如客户端无法导入，请手动填写 path/encryption/finalmask。"
    fi
    if [[ -f "$STATE_FILE" ]] && jq -e ".${VLESS_FULLSTACK_STATE_KEY}.finalmask_enabled == true" "$STATE_FILE" >/dev/null 2>&1; then
        echo
        echo "提示: FullStack 链接较长，如客户端无法导入，请手动填写 path/encryption/reality/finalmask。"
    fi
}

# SS/SOCKS credentials come from the active config; use the same endpoint mapping
# as VLESS so NAT/custom external ports are honored for every exported protocol.
build_simple_proxy_share_link() {
    local tag="$1" scheme="$2" inbound port pair host link_port credentials user pass
    inbound="$(jq -c --arg tag "$tag" '.inbounds[]? | select(.tag == $tag)' "$CONFIG_FILE")" || return 1
    [[ -n "$inbound" ]] || return 1
    port="$(printf '%s' "$inbound" | jq -r '.port')"
    pair="$(link_endpoint_for_tag "$port" "$tag")" || return 1
    IFS=$'\t' read -r host link_port <<<"$pair"
    if [[ "$scheme" == "ss" ]]; then
        credentials="$(printf '%s' "$inbound" | jq -jr '.settings | .method + ":" + .password' | b64_url_no_pad)" || return 1
    else
        user="$(printf '%s' "$inbound" | jq -r '(.settings.users // .settings.accounts)[0].user')"
        pass="$(printf '%s' "$inbound" | jq -r '(.settings.users // .settings.accounts)[0].pass')"
        credentials="$(url_encode "$user"):$(url_encode "$pass")"
    fi
    printf '%s://%s@%s:%s' "$scheme" "$credentials" "$host" "$link_port"
    [[ "$scheme" != "ss" ]] || printf '#SS2022'
    return 0
}

# Print fresh URIs for each requested address family. Never reuse saved links:
# their endpoint/port/address family may no longer match the requested export.
render_export_links() {
    local mode="${1:-dual}" count=0 kind custom emitted=""
    local CURRENT_LINK_VIEW_MODE="$mode"
    # Builders must load each profile from state, not leftover menu install vars.
    local VLESS_PORT="" REALITY_PORT="" XHTTP_PORT="" VLESS_ENC_FM_PORT=""
    local ENC_XHTTP_PORT="" ADVANCED_PORT="" HY2_PORT=""

    [[ -f "$CONFIG_FILE" ]] || {
        err "[导出] 未找到 config.json，请先安装协议。" >&2
        return 1
    }
    command -v jq >/dev/null 2>&1 || return 1
    init_state || return 1
    get_public_addresses
    host_candidates "$mode"
    custom="$(endpoint_custom_value)"

    _export_emit_link() {
        local uri="$1"
        [[ -n "$uri" && "$uri" != *YOUR_SERVER* ]] || return 0
        [[ "$emitted" != *"$uri"$'\n'* ]] || return 0
        printf '%s\n' "$uri"
        emitted+="$uri"$'\n'
        count=$((count + 1))
    }

    _export_emit_profile_links() {
        local tag="$1" state_key="$2" link scope
        shift 2
        inbound_exists "$tag" || return 0
        if [[ -n "$custom" ]]; then
            # A custom endpoint can be an external relay/NAT address; its family
            # need not match the listener or a locally detected public address.
            link="$("$@" 2>/dev/null)" && _export_emit_link "$link"
        else
            scope="$(inbound_listen_scope "$tag" "$state_key")"
            if [[ "$mode" != "ipv6" && -n "$IPV4_HOST" && "$scope" != "ipv6" ]]; then
                CURRENT_LINK_VIEW_MODE="ipv4"
                link="$("$@" 2>/dev/null)" && _export_emit_link "$link"
            fi
            if should_print_ipv6_link "$mode" "$tag" "$state_key"; then
                CURRENT_LINK_VIEW_MODE="ipv6"
                link="$("$@" 2>/dev/null)" && _export_emit_link "$link"
            fi
        fi
        return 0
    }

    _export_emit_profile_links "$SS_TAG" ss2022 build_simple_proxy_share_link "$SS_TAG" ss
    _export_emit_profile_links "$VLESS_TAG" vless_encryption build_vless_enc_share_link
    _export_emit_profile_links "$REALITY_TAG" "$REALITY_STATE_KEY" build_reality_share_link
    _export_emit_profile_links "$VLESS_XHTTP_FM_TAG" "$VLESS_XHTTP_FM_STATE_KEY" build_vless_xhttp_finalmask_share_link
    _export_emit_profile_links "$VLESS_ENC_FM_TAG" "$VLESS_ENC_FM_STATE_KEY" build_vless_enc_finalmask_share_link
    _export_emit_profile_links "$VLESS_ENC_XHTTP_TAG" "$VLESS_ENC_XHTTP_STATE_KEY" build_vless_enc_xhttp_share_link
    for kind in xhttp-reality enc-reality fullstack; do
        _export_emit_profile_links "$(advanced_profile_tag "$kind")" "$(advanced_profile_state_key "$kind")" build_advanced_share_link "$kind"
    done
    _export_emit_profile_links "$HY2_TAG" "$HY2_STATE_KEY" build_hysteria2_share_link
    _export_emit_profile_links "$SOCKS_TAG" socks5 build_simple_proxy_share_link "$SOCKS_TAG" socks5

    if [[ "$count" -eq 0 ]]; then
        err "[导出] 未找到可导出的分享链接，请检查协议状态与公网 endpoint。" >&2
        return 1
    fi
}

write_or_print_export() {
    local output_path="${1:-}"
    local content

    content="$(cat)"
    if [[ -n "$output_path" ]]; then
        printf '%s\n' "$content" >"$output_path" || {
            err "[导出] 写入失败: $output_path"
            return 1
        }
        chmod 600 "$output_path" 2>/dev/null || true
        ok "[导出] 已写入: $output_path"
    else
        printf '%s\n' "$content"
    fi
}

run_export_command() {
    local action="${1:-report}"
    local output=""
    local mode="dual"
    local links_body

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                output="${2:-}"
                [[ -n "$output" ]] || {
                    err "[导出] --output 需要路径"
                    return 1
                }
                shift; shift
                ;;
            ipv4 | ipv6 | dual)
                mode="$1"
                shift
                ;;
            --mode)
                mode="${2:-}"
                case "$mode" in
                    ipv4 | ipv6 | dual) ;;
                    *)
                        err "[导出] --mode 仅支持 ipv4|ipv6|dual"
                        return 1
                        ;;
                esac
                shift; shift
                ;;
            *)
                err "[失败] 未知 export 参数: $1"
                echo "用法: ike export report|clients|links [--output PATH] [ipv4|ipv6|dual]"
                return 1
                ;;
        esac
    done

    case "$action" in
        report)
            render_export_report | write_or_print_export "$output"
            ;;
        clients)
            render_export_clients | write_or_print_export "$output"
            ;;
        links | link | share)
            # Capture pure URI lines first so empty/error does not create a blank file.
            links_body="$(render_export_links "$mode")" || return 1
            if [[ -n "$output" ]]; then
                printf '%s\n' "$links_body" >"$output" || {
                    err "[导出] 写入失败: $output"
                    return 1
                }
                chmod 600 "$output" 2>/dev/null || true
                ok "[导出] 已写入: $output"
            else
                printf '%s\n' "$links_body"
            fi
            ;;
        *)
            err "[失败] 未知 export 目标: $action"
            echo "用法: ike export report|clients|links [--output PATH] [ipv4|ipv6|dual]"
            return 1
            ;;
    esac
}
