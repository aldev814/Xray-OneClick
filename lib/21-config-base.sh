#!/usr/bin/env bash
# Xray-OneClick config.json lifecycle: init, backup, validate, apply.

# init_config 会被 set_enhanced_safety_block / set_china_direct_block 反向调用
# （默认开启 18/19 逻辑），不加保护会无限递归打爆调用栈。递归入口直接返回。
init_config() {
    if [[ "${INIT_CONFIG_RUNNING:-false}" == "true" ]]; then
        return 0
    fi
    local rc=0
    INIT_CONFIG_RUNNING="true"
    _init_config_impl || rc=$?
    INIT_CONFIG_RUNNING="false"
    return "$rc"
}

_init_config_impl() {
    local broken tmp

    mkdir -p "$CONFIG_DIR" || {
        err "[配置] 创建配置目录失败: $CONFIG_DIR"
        return 1
    }
    command -v jq >/dev/null 2>&1 || {
        err "[配置] 缺少 jq，无法初始化配置。"
        return 1
    }

    if [[ -f "$CONFIG_FILE" ]] && ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
        broken="$(mktemp "${CONFIG_FILE}.broken.$(date +%Y%m%d%H%M%S).XXXXXX")" || return 1
        rm -f "$broken"
        if ! mv "$CONFIG_FILE" "$broken"; then
            err "[配置] 无效配置备份失败，已停止初始化: $CONFIG_FILE"
            return 1
        fi
        err "[配置] 发现无效 JSON，已备份到: $broken"
    fi

    if [[ ! -f "$CONFIG_FILE" ]]; then
        tmp="$(config_temp_file)" || return 1
        if ! cat >"$tmp" <<'JSON'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
JSON
        then
            rm -f "$tmp"
            err "[配置] 创建基础配置失败: $CONFIG_FILE"
            return 1
        fi
        if ! jq empty "$tmp" >/dev/null 2>&1 || ! mv "$tmp" "$CONFIG_FILE"; then
            rm -f "$tmp"
            err "[配置] 提交基础配置失败: $CONFIG_FILE"
            return 1
        fi
    fi

    tmp="$(config_temp_file)" || return 1
    if ! jq '
      .log //= {"loglevel":"warning"} |
      .inbounds //= [] |
      .outbounds //= [{"tag":"direct","protocol":"freedom"}]
    ' "$CONFIG_FILE" >"$tmp"; then
        rm -f "$tmp"
        err "[配置] 规范化配置失败。"
        return 1
    fi
    if ! mv "$tmp" "$CONFIG_FILE"; then
        rm -f "$tmp"
        err "[配置] 写入规范化配置失败。"
        return 1
    fi
    ensure_default_safety_blocks || return 1
    # 默认开启增强安全屏蔽（菜单 19）与中国大陆直连屏蔽增强模式（菜单 18）。
    # defer 模式只写配置不重启服务（此时服务可能尚未创建），不覆盖用户手动设置。
    if ! enhanced_safety_block_enabled && ! enhanced_block_user_set; then
        set_enhanced_safety_block "true" "defer" || return 1
    fi
    if [[ "$(china_direct_block_rule_mode)" != "enhanced" ]] && ! cnblock_user_set; then
        if [[ -f "$ASSET_DIR/geoip.dat" && -f "$ASSET_DIR/geosite.dat" ]]; then
            set_china_direct_block "enhanced" "defer" || return 1
        fi
    fi
    ensure_config_security || return 1
}

enhanced_block_user_set() {
    [[ -f "$STATE_FILE" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    [[ "$(jq -r '.enhanced_block_user_set // false' "$STATE_FILE" 2>/dev/null)" == "true" ]]
}

cnblock_user_set() {
    [[ -f "$STATE_FILE" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    [[ "$(jq -r '.cnblock_user_set // false' "$STATE_FILE" 2>/dev/null)" == "true" ]]
}

backup_config() {
    local backup_path

    [[ -f "$CONFIG_FILE" ]] || return 0
    backup_path="$(mktemp "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S).XXXXXX")" || return 1
    if ! cp -a "$CONFIG_FILE" "$backup_path"; then
        rm -f "$backup_path"
        return 1
    fi
}

restore_latest_config_backup() {
    local latest_backup candidate

    latest_backup=""
    for candidate in "${CONFIG_FILE}.bak."*; do
        [[ -f "$candidate" ]] || continue
        if [[ -z "$latest_backup" || "$candidate" -nt "$latest_backup" ]]; then
            latest_backup="$candidate"
        fi
    done
    if [[ -z "$latest_backup" || ! -f "$latest_backup" ]]; then
        err "[回滚] 未找到可恢复的配置备份: ${CONFIG_FILE}.bak.*"
        return 1
    fi

    info "[回滚] 正在恢复最近备份: $latest_backup"
    if ! cp -a "$latest_backup" "$CONFIG_FILE"; then
        err "[回滚] 恢复配置文件失败。"
        return 1
    fi
    ensure_config_security || return 1

    if ! validate_config_file; then
        err "[回滚] 恢复失败：备份配置校验未通过。"
        return 1
    fi

    ok "[回滚] 恢复成功，备份配置校验通过。"
}

rollback_config_after_state_failure() {
    local context="${1:-配置状态}"

    err "[失败] [${context}] 配置已生效，但状态写入失败。"
    err "[回滚] 正在恢复安装前配置。"
    if restore_latest_config_backup && restart_service; then
        ok "[回滚] 配置与服务已恢复。"
    else
        err "[回滚] 自动恢复失败，请检查 $CONFIG_FILE 和 ${CONFIG_FILE}.bak.*。"
    fi
    return 1
}

export_current_config_backup() {
    local timestamp config_backup state_backup

    [[ -f "$CONFIG_FILE" ]] || {
        err "[失败] 未找到配置文件: $CONFIG_FILE"
        return 1
    }

    timestamp="$(date +%Y%m%d%H%M%S)"
    config_backup="$(mktemp "/root/xray-config-backup-${timestamp}.json.XXXXXX")" || return 1

    if ! cp -a "$CONFIG_FILE" "$config_backup"; then
        err "[失败] 导出配置备份失败: $config_backup"
        return 1
    fi
    chmod 600 "$config_backup" 2>/dev/null || true

    ok "[备份] config.json: $config_backup"

    if [[ -f "$STATE_FILE" ]]; then
        state_set_meta_action "导出配置备份" || err "[状态] 记录备份动作失败，配置备份已继续导出。"
        state_backup="$(mktemp "/root/xray-state-backup-${timestamp}.json.XXXXXX")" || return 1
        if ! cp -a "$STATE_FILE" "$state_backup"; then
            err "[失败] 导出状态备份失败: $state_backup"
            return 1
        fi
        chmod 600 "$state_backup" 2>/dev/null || true
        ok "[备份] installer-state.json: $state_backup"
    else
        info "[备份] 未找到状态文件，已跳过: $STATE_FILE"
    fi
}

validate_config_file() {
    local log_file

    if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
        err "[错误] 配置文件 JSON 无效: $CONFIG_FILE"
        return 1
    fi

    if [[ -x "$BIN_PATH" ]]; then
        log_file="$(mktemp)" || {
            err "[错误] 无法创建 Xray 配置校验日志。"
            return 1
        }
        if ! "$BIN_PATH" run -test -c "$CONFIG_FILE" >"$log_file" 2>&1; then
            err "[错误] Xray 校验配置失败:"
            cat "$log_file"
            rm -f "$log_file"
            return 1
        fi
        rm -f "$log_file"
    fi

    return 0
}
