#!/usr/bin/env bash
# Interactive main menu. Action IDs retain the original installation handlers.

render_menu() {
    clear 2>/dev/null || true
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}  Xray-OneClick · ike  ${SCRIPT_VERSION}${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo "系统: $OS_TYPE | 服务: $INIT_SYSTEM | 架构: $ARCH"
    echo "----------------------------------------------"
    echo " 1. 协议安装"
    echo " 2. Tunnel 中转管理"
    echo " 3. 配置与分享链接"
    echo " 4. 服务与诊断"
    echo " 5. 安全与路由"
    echo " 6. 备份与配置迁移"
    echo " 7. 重置密钥 / 密码"
    echo " 8. 核心与脚本更新"
    echo -e "${RED} 9. 卸载 / 清理${PLAIN}"
    echo " 0. 退出"
    echo "----------------------------------------------"
}

menu_section_items() {
    case "$1" in
        protocols)
            cat <<EOF
|常用协议
1|VLESS TCP REALITY|5|$REALITY_TAG
2|Shadowsocks 2022|2|$SS_TAG
3|Hysteria2|13|$HY2_TAG
4|SOCKS5|12|$SOCKS_TAG
|VLESS Encryption 组合
5|Encryption · TCP|4|$VLESS_TAG
6|Encryption + XHTTP|6|$VLESS_ENC_XHTTP_TAG
7|Encryption + FinalMask（sudoku）|8|$VLESS_ENC_FM_TAG
8|Encryption + XHTTP + FinalMask|7|$VLESS_XHTTP_FM_TAG
|REALITY 高级组合
9|XHTTP + REALITY|9|$VLESS_XHTTP_REALITY_TAG
10|Encryption + REALITY|10|$VLESS_ENC_REALITY_TAG
11|Encryption + XHTTP + REALITY + FinalMask|11|$VLESS_FULLSTACK_TAG
|其他安装选项
12|Shadowsocks 2022（检测 IPv6 / 双栈）|3|$SS_TAG
EOF
            ;;
        config)
            cat <<'EOF'
1|查看当前配置与链接|14
2|仅输出分享链接|links
3|查看客户端参数|clients
4|链接显示模式（IPv4 / IPv6 / 双栈）|15
5|查看自定义入口地址|endpoint
EOF
            ;;
        service)
            cat <<'EOF'
1|服务状态|status
2|重启服务|restart
3|查看日志|logs
4|校验当前配置|config-test
5|完整诊断|doctor
EOF
            ;;
        safety)
            cat <<'EOF'
1|中国大陆直连屏蔽|18
2|增强安全屏蔽|19
EOF
            ;;
        backup)
            cat <<'EOF'
1|导出配置备份|20
2|预览旧配置迁移（不修改）|migrate-preview
3|执行旧配置迁移|migrate
EOF
            ;;
        update)
            cat <<'EOF'
1|安装 / 更新 Xray 核心|1
2|更新 ike 脚本|upgrade
3|查看版本|version
EOF
            ;;
    esac
}

show_menu_section() {
    local section="$1" title="$2" items choice key label action tag selected marker
    items="$(menu_section_items "$section")"
    while true; do
        clear 2>/dev/null || true
        echo -e "${GREEN}[$title]${PLAIN}"
        echo "----------------------------------------------"
        while IFS='|' read -r key label action tag; do
            if [[ -z "$key" ]]; then
                echo -e "\n${YELLOW}${label}${PLAIN}"
                continue
            fi
            marker=""
            if [[ -n "$tag" ]] && inbound_exists "$tag"; then marker=" [已配置]"; fi
            printf ' %2s. %s%s\n' "$key" "$label" "$marker"
        done <<<"$items"
        echo "  0. 返回主菜单"
        echo "----------------------------------------------"
        read -r -p "请选择: " choice || return 1
        [[ "$choice" != "0" ]] || return 0
        selected=""
        while IFS='|' read -r key label action tag; do
            if [[ -n "$key" && "$choice" == "$key" ]]; then selected="$action"; break; fi
        done <<<"$items"
        if [[ -n "$selected" ]]; then
            run_menu_action "$selected" || err "[失败] 操作未完成，请查看上方提示。"
            [[ "$selected" != "upgrade" ]] || info "脚本更新后，请退出菜单并重新运行 ike。"
        else
            err "无效选项。"
        fi
        read -r -p "按回车返回当前菜单..." choice || return 1
    done
}

run_menu_action() {
    case "$1" in
    1)
        update_xray_core || err "[失败] Xray 核心安装/更新未完成，请查看上方错误信息。"
        ;;
    2)
        if ! { prepare_system && configure_ss2022 "ipv4" && install_ss2022; }; then
            err "[失败] Shadowsocks 2022 安装未完成，请查看上方错误信息。"
        fi
        ;;
    3)
        if ! prepare_system; then
            err "[失败] IPv6 + Shadowsocks 2022 安装未完成，请查看上方错误信息。"
        else
            if check_ipv6_status; then
                if ! { configure_ss2022 "ipv6" && install_ss2022; }; then
                    err "[失败] IPv6 + Shadowsocks 2022 安装未完成，请查看上方错误信息。"
                fi
            else
                info "[IPv6] 未检测到可用全局 IPv6 地址，请先在服务器开通 IPv6 后重试。"
                err "[失败] IPv6 + Shadowsocks 2022 安装未完成。"
            fi
        fi
        ;;
    4)
        if ! { prepare_system && configure_vless_encryption && install_vless_encryption; }; then
            err "[失败] VLESS Encryption 安装未完成，请查看上方错误信息。"
        fi
        ;;
    5)
        if ! { prepare_system && configure_reality "interactive" && install_reality; }; then
            err "[失败] VLESS TCP REALITY 安装未完成，请查看上方错误信息。"
        fi
        ;;
    6)
        if ! { prepare_system && configure_vless_enc_xhttp "interactive" && install_vless_enc_xhttp; }; then
            err "[失败] VLESS Encryption + XHTTP 安装未完成，请查看上方错误信息。"
        fi
        ;;
    7)
        if ! { prepare_system && configure_vless_xhttp_finalmask "interactive" && install_vless_xhttp_finalmask; }; then
            err "[失败] VLESS Encryption + XHTTP + FinalMask 安装未完成，请查看上方错误信息。"
        fi
        ;;
    8)
        if ! { prepare_system && configure_vless_enc_finalmask "interactive" && install_vless_enc_finalmask; }; then
            err "[失败] VLESS Encryption + FinalMask 安装未完成，请查看上方错误信息。"
        fi
        ;;
    9)
        if ! { prepare_system && configure_advanced_profile "xhttp-reality" "interactive" && install_advanced_profile "xhttp-reality"; }; then
            err "[失败] VLESS XHTTP + REALITY 安装未完成，请查看上方错误信息。"
        fi
        ;;
    10)
        if ! { prepare_system && configure_advanced_profile "enc-reality" "interactive" && install_advanced_profile "enc-reality"; }; then
            err "[失败] VLESS Encryption + REALITY 安装未完成，请查看上方错误信息。"
        fi
        ;;
    11)
        if ! { prepare_system && configure_advanced_profile "fullstack" "interactive" && install_advanced_profile "fullstack"; }; then
            err "[失败] VLESS Encryption + XHTTP + REALITY + FinalMask 安装未完成，请查看上方错误信息。"
        fi
        ;;
    12)
        if ! { prepare_system && install_socks5; }; then
            err "[失败] SOCKS5 安装未完成，请查看上方错误信息。"
        fi
        ;;
    13)
        if ! { prepare_system && configure_hysteria2 "interactive" && install_hysteria2; }; then
            err "[失败] Hysteria2 安装未完成，请查看上方错误信息。"
        fi
        ;;
    14)
        view_config || err "[失败] 查看当前配置链接失败，请查看上方错误信息。"
        ;;
    15)
        set_link_view_mode || err "[失败] 设置链接显示模式失败，请查看上方错误信息。"
        ;;
    16)
        if ! { prepare_system && reset_secrets; }; then
            err "[失败] 重置密钥/密码未完成，请查看上方错误信息。"
        fi
        ;;
    17)
        uninstall || err "[失败] 卸载/清理未完成，请查看上方错误信息。"
        ;;
    18)
        configure_china_direct_block || err "[失败] 中国大陆直连屏蔽设置未完成，请查看上方错误信息。"
        ;;
    19)
        configure_enhanced_safety_block || err "[失败] 增强安全屏蔽设置未完成，请查看上方错误信息。"
        ;;
    20)
        export_current_config_backup || err "[失败] 导出当前配置备份未完成，请查看上方错误信息。"
        ;;
    21)
        configure_forward_menu || err "[失败] Tunnel 中转管理未完成，请查看上方错误信息。"
        ;;
    links) render_export_links dual ;;
    clients) render_export_clients ;;
    endpoint) run_endpoint_command show ;;
    status) run_service_command status ;;
    restart) run_service_command restart ;;
    logs) run_service_command logs ;;
    config-test) run_config_command test ;;
    doctor) run_doctor_command all ;;
    migrate-preview) run_migrate_command --dry-run ;;
    migrate) run_migrate_command ;;
    upgrade) run_upgrade_command ;;
    version) show_version ;;
    *) err "错误选项。" ;;
    esac
}

show_menu() {
    install_shortcut
    local choice
    while true; do
        render_menu
        read -r -p "请选择 [0-9]: " choice || return 0
        case "$choice" in
            1) show_menu_section protocols "协议安装" || return 0 ;;
            2) run_menu_action 21; pause_return_menu ;;
            3) show_menu_section config "配置与分享链接" || return 0 ;;
            4) show_menu_section service "服务与诊断" || return 0 ;;
            5) show_menu_section safety "安全与路由" || return 0 ;;
            6) show_menu_section backup "备份与配置迁移" || return 0 ;;
            7) run_menu_action 16; pause_return_menu ;;
            8) show_menu_section update "核心与脚本更新" || return 0 ;;
            9) run_menu_action 17; pause_return_menu ;;
            0) return 0 ;;
            *) err "无效选项。"; pause_return_menu ;;
        esac
    done
}
