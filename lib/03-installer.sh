#!/usr/bin/env bash
# Installer self-deployment: ike shortcut and lib/ sync.

install_shortcut() {
    local script_source="${IKE_INSTALLER_DIR}/install.sh"
    local source_lib destination_lib tmp_installer tmp_shortcut tmp_lib old_lib module

    script_source="$(readlink -f "$script_source" 2>/dev/null || printf '%s' "$script_source")"

    mkdir -p "$(dirname "$SHORTCUT_PATH")" "$INSTALLER_DIR" || return 1

    if [[ -f "$script_source" && -r "$script_source" ]]; then
        if [[ -d "${IKE_INSTALLER_DIR}/lib" ]]; then
            mkdir -p "${INSTALLER_DIR}/lib" || return 1
            source_lib="$(readlink -f "${IKE_INSTALLER_DIR}/lib" 2>/dev/null || printf '%s' "${IKE_INSTALLER_DIR}/lib")"
            destination_lib="$(readlink -f "${INSTALLER_DIR}/lib" 2>/dev/null || printf '%s' "${INSTALLER_DIR}/lib")"
            if [[ "$source_lib" != "$destination_lib" ]]; then
                tmp_lib="$(mktemp -d "${INSTALLER_DIR}/lib.new.XXXXXX")" || return 1
                if ! cp -a "${source_lib}/." "$tmp_lib/"; then
                    remove_managed_tree "$tmp_lib" >/dev/null 2>&1 || true
                    return 1
                fi
                for module in "$tmp_lib"/*.sh; do
                    [[ -f "$module" ]] || continue
                    if ! bash -n "$module"; then
                        remove_managed_tree "$tmp_lib" >/dev/null 2>&1 || true
                        return 1
                    fi
                done
                old_lib="$(mktemp -d "${INSTALLER_DIR}/lib.old.XXXXXX")" || {
                    remove_managed_tree "$tmp_lib" >/dev/null 2>&1 || true
                    return 1
                }
                if ! rmdir "$old_lib"; then
                    remove_managed_tree "$tmp_lib" >/dev/null 2>&1 || true
                    remove_managed_tree "$old_lib" >/dev/null 2>&1 || true
                    return 1
                fi
                if ! mv "$destination_lib" "$old_lib"; then
                    remove_managed_tree "$tmp_lib" >/dev/null 2>&1 || true
                    return 1
                fi
                if ! mv "$tmp_lib" "$destination_lib"; then
                    mv "$old_lib" "$destination_lib" >/dev/null 2>&1 || true
                    remove_managed_tree "$tmp_lib" >/dev/null 2>&1 || true
                    return 1
                fi
                remove_managed_tree "$old_lib" >/dev/null 2>&1 || true
            fi
        fi
        if [[ "$script_source" != "$INSTALLER_PATH" ]]; then
            tmp_installer="$(mktemp "${INSTALLER_PATH}.tmp.XXXXXX")" || return 1
            cp "$script_source" "$tmp_installer" || {
                rm -f "$tmp_installer"
                return 1
            }
            chmod 755 "$tmp_installer" || {
                rm -f "$tmp_installer"
                return 1
            }
            mv "$tmp_installer" "$INSTALLER_PATH" || {
                rm -f "$tmp_installer"
                return 1
            }
        fi
        chmod +x "$INSTALLER_PATH" || return 1
    elif [[ ! -f "$INSTALLER_PATH" ]]; then
        tmp_installer="$(mktemp "${INSTALLER_PATH}.tmp.XXXXXX")" || return 1
        if ! cat >"$tmp_installer" <<EOF
#!/bin/bash
SCRIPT_URL="${RAW_SCRIPT_URL}"
TMP_SCRIPT="\$(mktemp)"
trap 'rm -f "\$TMP_SCRIPT"' EXIT
curl -fsSL "\$SCRIPT_URL" -o "\$TMP_SCRIPT" || exit 1
bash "\$TMP_SCRIPT" "\$@"
EOF
        then
            rm -f "$tmp_installer"
            return 1
        fi
        chmod 755 "$tmp_installer" || {
            rm -f "$tmp_installer"
            return 1
        }
        mv "$tmp_installer" "$INSTALLER_PATH" || {
            rm -f "$tmp_installer"
            return 1
        }
    fi

    tmp_shortcut="$(mktemp "${SHORTCUT_PATH}.tmp.XXXXXX")" || return 1
    if ! cat >"$tmp_shortcut" <<EOF
#!/bin/bash
if [[ ! -f "$INSTALLER_PATH" ]]; then
    echo "未找到安装器脚本 $INSTALLER_PATH，请重新上传 install.sh 并执行安装。" >&2
    exit 1
fi
exec bash "$INSTALLER_PATH" "\$@"
EOF
    then
        rm -f "$tmp_shortcut"
        return 1
    fi
    chmod 755 "$tmp_shortcut" || {
        rm -f "$tmp_shortcut"
        return 1
    }
    mv "$tmp_shortcut" "$SHORTCUT_PATH" || {
        rm -f "$tmp_shortcut"
        return 1
    }
}

# ---------------------------------------------------------------------------
# ike upgrade：自更新安装器（install.sh + lib/）到仓库最新版本。
# 流程：拉取远程 VERSION 比对 → 下载新 install.sh 与全部 lib/ 模块到
# 临时目录 → 逐个 bash -n 校验 → 原子交换部署目录。任一步失败保持原状。
# ---------------------------------------------------------------------------

_ike_upgrade_fetch() {
    local url="$1"
    local output="$2"

    # raw.githubusercontent.com 有 ~5 分钟 CDN 缓存；加时间戳查询参数
    # 破缓存，避免多文件部署拿到新旧混合版本。
    url="${url}?t=$(date +%s)"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -qT 60 -O "$output" "$url"
    else
        err "[升级] 缺少 curl 或 wget，无法下载。"
        return 1
    fi
}

run_upgrade_command() {
    local force="false"
    local remote_version current_version staged_version
    local version_tmp staging old_dir module module_name

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force="true"
                shift
                ;;
            *)
                err "[失败] 未知 upgrade 参数: $1"
                echo "用法: ike upgrade [--force]"
                return 1
                ;;
        esac
    done

    if [[ ! -d "$INSTALLER_DIR" ]]; then
        err "[升级] 未找到安装器目录: $INSTALLER_DIR"
        err "[提示] 请重新执行一键安装脚本部署 ike。"
        return 1
    fi

    current_version="$SCRIPT_VERSION"
    info "[升级] 当前脚本版本: ${current_version}"
    info "[升级] 正在检查 ${IKE_REPOSITORY}@${IKE_REF} ..."

    version_tmp="$(mktemp "${INSTALLER_DIR}/.version.tmp.XXXXXX")" || {
        err "[升级] 创建临时文件失败。"
        return 1
    }
    if ! _ike_upgrade_fetch "${IKE_RAW_BASE}/VERSION" "$version_tmp"; then
        rm -f "$version_tmp"
        err "[升级] 获取远程 VERSION 失败，请检查网络或仓库设置。"
        return 1
    fi
    remote_version="$(tr -d ' \t\r\n' <"$version_tmp")"
    rm -f "$version_tmp"
    [[ -n "$remote_version" ]] || {
        err "[升级] 远程 VERSION 为空，已中止。"
        return 1
    }
    info "[升级] 远程脚本版本: ${remote_version}"

    if [[ "$remote_version" == "$current_version" && "$force" != "true" ]]; then
        ok "[升级] 已是最新版本 (${current_version})，无需更新。"
        return 0
    fi
    [[ "$remote_version" != "$current_version" ]] && info "[升级] 发现新版本: ${current_version} -> ${remote_version}"

    # 下载 install.sh + 当前部署副本的全部 lib/ 模块到暂存目录并校验
    staging="$(mktemp -d "${INSTALLER_DIR}/upgrade.new.XXXXXX")" || {
        err "[升级] 创建暂存目录失败。"
        return 1
    }
    if ! _ike_upgrade_fetch "${IKE_RAW_BASE}/install.sh" "${staging}/install.sh" ||
        [[ ! -s "${staging}/install.sh" ]] || ! bash -n "${staging}/install.sh"; then
        remove_managed_tree "$staging" >/dev/null 2>&1 || true
        err "[升级] 下载或校验 install.sh 失败，已保持当前版本。"
        return 1
    fi

    mkdir -p "${staging}/lib" || {
        remove_managed_tree "$staging" >/dev/null 2>&1 || true
        return 1
    }
    shopt -s nullglob
    local -a modules=("${INSTALLER_DIR}/lib/"*.sh)
    shopt -u nullglob
    [[ ${#modules[@]} -gt 0 ]] || {
        remove_managed_tree "$staging" >/dev/null 2>&1 || true
        err "[升级] 部署目录缺少 lib/ 模块: ${INSTALLER_DIR}/lib"
        return 1
    }
    for module in "${modules[@]}"; do
        module_name="${module##*/}"
        if ! _ike_upgrade_fetch "${IKE_RAW_BASE}/lib/${module_name}" "${staging}/lib/${module_name}" ||
            [[ ! -s "${staging}/lib/${module_name}" ]] || ! bash -n "${staging}/lib/${module_name}"; then
            remove_managed_tree "$staging" >/dev/null 2>&1 || true
            err "[升级] 下载或校验 lib/${module_name} 失败，已保持当前版本。"
            return 1
        fi
    done

    # 暂存模块的 SCRIPT_VERSION 必须与远程 VERSION 一致，防止 CDN 缓存
    # 返回的新旧混合文件被部署成混版（constants 是旧版时会掩盖真实版本）。
    staged_version="$(grep -o 'SCRIPT_VERSION="[^"]*"' "${staging}/lib/01-constants.sh" 2>/dev/null | head -1 | cut -d'"' -f2)"
    if [[ -z "$staged_version" || "$staged_version" != "$remote_version" ]]; then
        remove_managed_tree "$staging" >/dev/null 2>&1 || true
        err "[升级] 暂存模块版本(${staged_version:-未知})与远程 VERSION(${remote_version})不一致，可能命中 CDN 缓存，已中止。"
        err "[提示] 请稍等几分钟后重试，或使用 ike upgrade --force。"
        return 1
    fi

    # 原子交换：旧目录改名保留为回滚点，暂存目录顶上，成功后清理旧目录
    old_dir="${INSTALLER_DIR}.old.$(date +%Y%m%d%H%M%S)"
    if ! mv "$INSTALLER_DIR" "$old_dir" || ! mv "$staging" "$INSTALLER_DIR"; then
        err "[升级] 替换部署目录失败，正在尝试恢复。"
        [[ -d "$old_dir" && ! -d "$INSTALLER_DIR" ]] && mv "$old_dir" "$INSTALLER_DIR" >/dev/null 2>&1 || true
        remove_managed_tree "$staging" >/dev/null 2>&1 || true
        return 1
    fi
    chmod 755 "${INSTALLER_DIR}/install.sh" 2>/dev/null || true
    remove_managed_tree "$old_dir" >/dev/null 2>&1 || true

    state_set_meta_action "脚本自升级 ${current_version} -> ${remote_version}" 2>/dev/null || true
    ok "[完成] 脚本已升级: ${current_version} -> ${remote_version}"
    info "[提示] 新版本已生效；如当前处于交互菜单，建议退出后重新运行 ike。"
    return 0
}
