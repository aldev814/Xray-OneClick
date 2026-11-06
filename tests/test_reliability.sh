#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
# shellcheck source=../install.sh
source "${REPO_ROOT}/install.sh"

fail() { echo "[FAIL] $*" >&2; exit 1; }

# A complete target release with a newly introduced module. The old deployment
# deliberately has a module absent from the target release.
prepare_upgrade() {
    local root="$1"
    TARGET_DIR="$root/target"
    INSTALLER_DIR="$root/deployed"
    IKE_REPOSITORY="example/installer"
    IKE_REF="main"
    TEST_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    mkdir -p "$TARGET_DIR" "$INSTALLER_DIR/lib"
    cp "$REPO_ROOT/install.sh" "$TARGET_DIR/install.sh"
    cp -a "$REPO_ROOT/lib" "$TARGET_DIR/lib"
    sed '/^IKE_LIB_MODULES=(/a\
    "98-new-module.sh"
' "$TARGET_DIR/install.sh" >"$TARGET_DIR/install.new"
    mv "$TARGET_DIR/install.new" "$TARGET_DIR/install.sh"
    printf '%s\n' 'NEW_MODULE_LOADED=true' >"$TARGET_DIR/lib/98-new-module.sh"
    printf '\n_ike_source_lib "98-new-module" || exit 1\n' >>"$TARGET_DIR/lib/00-bootstrap.sh"
    sed 's/^SCRIPT_VERSION=.*/SCRIPT_VERSION="9.9.9"/' "$TARGET_DIR/lib/01-constants.sh" >"$TARGET_DIR/constants.new"
    mv "$TARGET_DIR/constants.new" "$TARGET_DIR/lib/01-constants.sh"
    printf '%s\n' 9.9.9 >"$TARGET_DIR/VERSION"
    printf '%s\n' old >"$INSTALLER_DIR/install.sh"
    printf '%s\n' obsolete >"$INSTALLER_DIR/lib/99-obsolete.sh"
    FETCH_LOG="$root/fetch.log"
    : >"$FETCH_LOG"
    state_set_meta_action() { :; }
    _ike_upgrade_fetch() {
        local url="$1" dest="$2" relative
        printf '%s\n' "$url" >>"$FETCH_LOG"
        if [[ "$url" == "https://api.github.com/repos/${IKE_REPOSITORY}/commits/main" ]]; then
            printf '{"sha":"%s"}\n' "$TEST_SHA" >"$dest"
            return 0
        fi
        [[ "$url" == "https://raw.githubusercontent.com/${IKE_REPOSITORY}/${TEST_SHA}/"* ]] || return 1
        relative="${url#"https://raw.githubusercontent.com/${IKE_REPOSITORY}/${TEST_SHA}/"}"
        cp "$TARGET_DIR/$relative" "$dest"
    }
}

assert_old_deployment() {
    [[ "$(cat "$INSTALLER_DIR/install.sh")" == old && -f "$INSTALLER_DIR/lib/99-obsolete.sh" ]] ||
        fail "失败后未保留原部署"
    [[ "$(find "$(dirname "$INSTALLER_DIR")" -maxdepth 1 -name 'deployed.upgrade.new.*' | wc -l)" -eq 0 ]] ||
        fail "失败后未清理暂存目录"
}

test_upgrade_success() (
    prepare_upgrade "$TEST_ROOT/success"
    run_upgrade_command >/dev/null || fail "完整升级失败"
    [[ -f "$INSTALLER_DIR/lib/98-new-module.sh" ]] || fail "目标新增模块未部署"
    [[ ! -e "$INSTALLER_DIR/lib/99-obsolete.sh" ]] || fail "目标已删除的模块仍存在"
    [[ "$(cat "$INSTALLER_DIR/COMMIT")" == "$TEST_SHA" ]] || fail "未记录固定提交"
    [[ "$(grep -c '/commits/main$' "$FETCH_LOG")" -eq 1 ]] || fail "目标提交应只解析一次"
    echo "[OK] 固定 SHA 升级与目标模块新增/删除"
)

test_upgrade_failures() (
    local mode
    for mode in missing syntax loader version manifest sha swap; do
        (
            prepare_upgrade "$TEST_ROOT/$mode"
            case "$mode" in
                missing) rm "$TARGET_DIR/lib/98-new-module.sh" ;;
                syntax) printf '%s\n' 'if then' >"$TARGET_DIR/lib/98-new-module.sh" ;;
                loader) printf '%s\n' 'return 1' >"$TARGET_DIR/lib/98-new-module.sh" ;;
                version) printf '%s\n' 9.9.8 >"$TARGET_DIR/VERSION" ;;
                manifest)
                    sed 's/98-new-module.sh/..\/escape.sh/' "$TARGET_DIR/install.sh" >"$TARGET_DIR/install.new"
                    mv "$TARGET_DIR/install.new" "$TARGET_DIR/install.sh"
                    ;;
                sha) TEST_SHA="invalid" ;;
                swap)
                    mv() {
                        if [[ "$1" == *'.upgrade.new.'* && "${2:-}" == "$INSTALLER_DIR" ]]; then
                            return 1
                        fi
                        command mv "$@"
                    }
                    ;;
            esac
            if run_upgrade_command >/dev/null 2>&1; then
                fail "异常 $mode 不应升级成功"
            fi
            assert_old_deployment
        ) || exit 1
    done
    echo "[OK] 升级下载/语法/加载/版本/清单/SHA/替换失败保持原部署"
)

test_exact_snapshot() (
    CONFIG_DIR="$TEST_ROOT/snapshot"
    CONFIG_FILE="$CONFIG_DIR/config.json"
    STATE_FILE="$CONFIG_DIR/state.json"
    ASSET_DIR="$CONFIG_DIR/assets"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' '{"before":true}' >"$CONFIG_FILE"
    printf '%s\n' '{"old_state":true}' >"$STATE_FILE"
    validate_config_file() { jq -e '.before == true' "$CONFIG_FILE" >/dev/null; }
    backup_config || fail "快照失败"
    printf '%s\n' '{"unrelated":true}' >"$CONFIG_FILE.bak.unrelated"
    touch -t 209901010000 "$CONFIG_FILE.bak.unrelated"
    printf '%s\n' '{"changed":true}' >"$CONFIG_FILE"
    printf '%s\n' '{"partial_state":true}' >"$STATE_FILE"
    restore_latest_config_backup >/dev/null || fail "精确恢复失败"
    jq -e '.old_state == true and (has("partial_state") | not)' "$STATE_FILE" >/dev/null || fail "状态未配套恢复"
    rm "$IKE_CONFIG_BACKUP"
    if restore_latest_config_backup >/dev/null 2>&1; then
        fail "本次快照丢失时不得改用无关备份"
    fi
    rm "$STATE_FILE"
    backup_config || fail "无 state 时快照失败"
    printf '%s\n' '{}' >"$STATE_FILE"
    restore_latest_config_backup >/dev/null || fail "无 state 快照恢复失败"
    [[ ! -e "$STATE_FILE" ]] || fail "恢复后应保留原先无 state 的状态"
    echo "[OK] 配置/state 配套快照、精确恢复与快照丢失保护"
)

test_operation_lock() (
    local rc=0
    if ((BASH_VERSINFO[0] < 4)); then
        echo "[SKIP] 并发锁行为测试需要 Linux 使用的 Bash 4+（BASHPID）"
        return 0
    fi
    export XRAY_ONECLICK_LOCK_DIR="$TEST_ROOT/operation.lock"
    (
        ike_acquire_lock || fail "首次加锁失败"
        (ike_acquire_lock >/dev/null 2>&1) && fail "第二个操作不应获得锁"
        ike_command_needs_lock service status && fail "服务状态查询不应加锁"
        ike_command_needs_lock xray version && fail "版本查询不应加锁"
        ike_command_needs_lock view || fail "写 state 的 view 应加锁"
        XRAY_ONECLICK_ENDPOINT=example.com ike_command_needs_lock xray version || fail "环境变量写入必须加锁"
        :
    ) || exit 1
    [[ ! -d "$XRAY_ONECLICK_LOCK_DIR" ]] || fail "正常退出未释放锁"
    (
        ike_acquire_lock || exit 1
        kill -TERM "$BASHPID"
    ) || rc=$?
    [[ "$rc" -eq 143 && ! -d "$XRAY_ONECLICK_LOCK_DIR" ]] || fail "TERM 退出未释放锁"
    echo "[OK] 并发互斥、查询分类和退出信号释放锁"
)

test_upgrade_success
test_upgrade_failures
test_exact_snapshot
test_operation_lock
echo "[OK] 可靠性测试全部通过"
