#!/usr/bin/env bash
# Migrate and uninstall CLI handlers.

migrate_old_config() {
    normalize_config_schema "${1:-false}"
}

detect_legacy_tags() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    jq -r '.inbounds[]?.tag // empty' "$CONFIG_FILE" 2>/dev/null | grep -E '^(forward-|tunnel-)' || true
}

normalize_config_schema() {
    local dry_run="${1:-false}"
    [[ -f "$CONFIG_FILE" ]] || return 0
    local tmp

    command -v jq >/dev/null 2>&1 || return 1
    tmp="$(config_temp_file)" || return 1
    if ! jq --arg min_client_ver "$REALITY_MIN_CLIENT_VERSION" \
      --argjson proxy_tags "$(jq -cn --args '$ARGS.positional' \
        "$VLESS_TAG" "$REALITY_TAG" "$VLESS_XHTTP_FM_TAG" \
        "$VLESS_XHTTP_REALITY_TAG" "$VLESS_ENC_REALITY_TAG" \
        "$VLESS_FULLSTACK_TAG" "$VLESS_ENC_FM_TAG" "$VLESS_ENC_XHTTP_TAG")" '
      def rename_field($old; $new):
        if has($old) then
          if has($new) and .[$new] != .[$old] then
            error("Conflicting config fields: " + $old + " / " + $new)
          else .[$new] = .[$old] | del(.[$old]) end
        else . end;
      def normalize_protocol_fields:
        if (.settings | type) == "object" then
          if .protocol == "vless" or .protocol == "hysteria" then
            .settings |= rename_field("clients"; "users")
          elif .protocol == "socks" then
            .settings |= rename_field("accounts"; "users")
          elif .protocol == "tunnel" or .protocol == "dokodemo-door" then
            .settings |= (rename_field("address"; "rewriteAddress") |
              rename_field("port"; "rewritePort") | rename_field("network"; "allowedNetwork"))
          else . end
        else . end;
      def normalize_reality_target:
        if (.streamSettings? | type) == "object" and .streamSettings.security == "reality" and (.streamSettings.realitySettings? | type) == "object" then
          (.streamSettings.realitySettings.target // .streamSettings.realitySettings.dest) as $target |
          if $target == null or $target == "" then
            error("REALITY inbound is missing target/dest: " + (.tag // "untagged"))
          else .streamSettings.realitySettings.target = $target end |
          .streamSettings.realitySettings.minClientVer = (.streamSettings.realitySettings.minClientVer // $min_client_ver) |
          del(.streamSettings.realitySettings.dest, .streamSettings.realitySettings.spiderX)
        else
          .
        end;
      # Preserve the requested destination when relaying nested TLS/REALITY.
      # Only migrate managed VLESS listeners whose sniffing is already enabled.
      def normalize_proxy_sniffing:
        if .protocol == "vless" and (.tag as $tag | $proxy_tags | index($tag)) != null
          and .sniffing.enabled == true then
          .sniffing.routeOnly = true
        else
          .
        end;
      if (.inbounds? | type) == "array" then
        .inbounds = [.inbounds[] | normalize_protocol_fields | normalize_reality_target | normalize_proxy_sniffing]
      else
        .
      end
    ' "$CONFIG_FILE" >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    local normalized
    normalized="$(normalize_finalmask_json "$(cat "$tmp")")" || {
        rm -f "$tmp"
        return 1
    }
    printf '%s\n' "$normalized" | jq . >"$tmp" || {
        rm -f "$tmp"
        return 1
    }
    if cmp -s "$CONFIG_FILE" "$tmp"; then
        rm -f "$tmp"
        diag_info "配置 schema 无需迁移"
        return 0
    fi
    if [[ "$dry_run" == "true" ]]; then
        rm -f "$tmp"
        diag_info "dry-run：检测到 config schema 迁移项，未修改配置"
        return 0
    fi
    mv "$tmp" "$CONFIG_FILE" || {
        rm -f "$tmp"
        return 1
    }
    rm -f "$tmp"
}

migrate_finalmask_state() {
    local dry_run="${1:-false}" tmp
    [[ -f "$STATE_FILE" ]] || return 0
    tmp="$(state_temp_file)" || return 1
    if ! normalize_finalmask_json "$(cat "$STATE_FILE")" | jq . >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if [[ "$dry_run" == "true" ]] || cmp -s "$STATE_FILE" "$tmp"; then
        rm -f "$tmp"
        return 0
    fi
    mv "$tmp" "$STATE_FILE" || { rm -f "$tmp"; return 1; }
}

run_migrate_command() {
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                ;;
            *)
                err "[失败] 未知 migrate 参数: $1"
                echo "用法: ike migrate [--dry-run]"
                return 1
                ;;
        esac
        shift
    done

    echo -e "\n${YELLOW}旧配置迁移检查${PLAIN}"
    echo "----------------------------------------"
    legacy_tags="$(detect_legacy_tags || true)"
    if [[ -n "$legacy_tags" ]]; then
        diag_info "检测到旧版 forward/tunnel tag: $(printf '%s' "$legacy_tags" | tr '\n' ' ')"
    fi
    if [[ "$dry_run" != "true" ]]; then
        backup_before_migration || {
            err "[迁移] 创建迁移备份失败。"
            return 1
        }
    fi
    migrate_old_config "$dry_run" || {
        err "[迁移] config schema 迁移失败。"
        [[ "$dry_run" == "true" ]] || restore_migration_backup >/dev/null 2>&1 || true
        return 1
    }
    if ! migrate_finalmask_state "$dry_run" || ! migrate_old_state "$dry_run"; then
        err "[迁移] state 迁移失败。"
        if [[ "$dry_run" != "true" ]]; then
            if restore_migration_backup; then
                diag_info "迁移失败，config/state 已恢复到迁移前快照。"
            else
                err "[迁移] 自动恢复迁移前快照失败。"
            fi
        fi
        return 1
    fi
    if [[ "$dry_run" != "true" ]] && ! validate_config_file; then
        err "[迁移] 配置校验失败，正在恢复迁移前的 config/state。"
        restore_migration_backup || err "[迁移] 自动恢复失败，请检查迁移备份。"
        return 1
    fi
}

create_purge_backup() {
    local backup_dir timestamp archive source
    local -a sources=()

    backup_dir="${XRAY_PURGE_BACKUP_DIR:-/var/backups/xray-oneclick}"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir" || return 1
    archive="$(mktemp "${backup_dir}/xray-oneclick-purge-${timestamp}.tar.gz.XXXXXX")" || return 1
    for source in "$CONFIG_DIR" "$(service_file_path)" "$BIN_PATH"; do
        [[ -e "$source" ]] && sources+=("$source")
    done
    if [[ ${#sources[@]} -gt 0 ]]; then
        tar -czf "$archive" "${sources[@]}" 2>/dev/null || {
            rm -f "$archive"
            return 1
        }
    else
        tar -czf "$archive" -T /dev/null 2>/dev/null || {
            rm -f "$archive"
            return 1
        }
    fi
    chmod 600 "$archive" || return 1
    echo "$archive"
}

run_uninstall_command() {
    local mode="keep-config"
    local dry_run="false"
    local yes="false"
    local service_file
    local -a remove_paths=()

    validate_xray_binary_path "$BIN_PATH" || return 1

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep-config)
                mode="keep-config"
                ;;
            --purge)
                mode="purge"
                ;;
            --dry-run)
                dry_run="true"
                ;;
            --yes | -y)
                yes="true"
                ;;
            *)
                err "[失败] 未知 uninstall 参数: $1"
                echo "用法: ike uninstall [--keep-config|--purge] [--dry-run] [--yes]"
                return 1
                ;;
        esac
        shift
    done

    service_file="$(service_file_path)"
    remove_paths=("$BIN_PATH" "$SHORTCUT_PATH" "$ASSET_DIR" "$INSTALLER_DIR")
    if [[ -f "$service_file" ]]; then
        if grep -q "Managed by Xray-OneClick" "$service_file"; then
            remove_paths+=("$service_file")
        else
            diag_warn "检测到非本项目 service，默认不删除: $service_file"
        fi
    fi
    if [[ "$mode" == "purge" ]]; then
        if [[ "$yes" != "true" ]] && ! env_truthy "${XRAY_ONECLICK_YES:-}"; then
            if [[ -t 0 ]]; then
                confirm_yes_no "purge 会删除配置、state 和日志，是否继续?" "n" || return 1
            else
                err "[卸载] purge 会删除配置和日志，非交互模式必须添加 --yes。"
                return 1
            fi
        fi
        remove_paths+=("$CONFIG_DIR" "$(log_dir_path)")
    else
        diag_info "keep-config: 保留 $CONFIG_FILE 和 $STATE_FILE"
    fi

    echo -e "\n${YELLOW}卸载预览${PLAIN}"
    printf '将删除: %s\n' "${remove_paths[@]}"
    [[ "$dry_run" == "true" ]] && {
        diag_info "dry-run：未删除任何文件"
        return 0
    }

    if [[ "$mode" == "purge" ]]; then
        local purge_backup
        purge_backup="$(create_purge_backup)" || {
            err "[卸载] 最终备份失败，已中止卸载。"
            return 1
        }
        diag_info "最终备份包: $purge_backup"
    fi
    stop_service || return 1
    if [[ "${INIT_SYSTEM:-}" == "openrc" ]] && command -v rc-update >/dev/null 2>&1; then
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
        rm -f "/etc/init.d/${SERVICE_NAME}"
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    for path in "${remove_paths[@]}"; do
        [[ -e "$path" ]] || continue
        case "$path" in
            "$ASSET_DIR" | "$INSTALLER_DIR" | "$CONFIG_DIR" | "$(log_dir_path)")
                remove_managed_tree "$path" || return 1
                ;;
            *)
                rm -f -- "$path" || return 1
                ;;
        esac
    done
    cleanup_installer_residuals || return 1
    command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 || true
    ok "[卸载] 完成。"
}
