# Xray-examples 协议组合覆盖清单

核对日期：2026-11-06。组合范围依据 [XTLS/Xray-examples](https://github.com/XTLS/Xray-examples) 当前主分支的示例目录，对照本脚本的安装及部署入口。

“已有”表示主要协议组合已提供安装流程，不代表完整复制示例的证书、反向代理、回落或客户端设置。“未加入”表示没有对应的一键安装/部署流程。

## 已有主要组合

| 组合 | 示例目录 | 对应脚本功能 |
| --- | --- | --- |
| VLESS + TCP + Vision + REALITY | [VLESS-TCP-XTLS-Vision-REALITY](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-XTLS-Vision-REALITY) | 已有普通 REALITY 安装；默认 Vision |
| VLESS + TCP + REALITY 的 defender 方案 | [VLESS-TCP-REALITY (without being stolen)](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-REALITY%20%28without%20being%20stolen%29) | 已有本地 defender 与 SNI 路由；不表示示例配置逐字相同 |
| VLESS + XHTTP + REALITY | [VLESS-XHTTP-Reality/minimal-steal_others](https://github.com/XTLS/Xray-examples/tree/main/VLESS-XHTTP-Reality/minimal-steal_others) | 已有高级组合入口 |
| Shadowsocks 2022 | [Shadowsocks-2022](https://github.com/XTLS/Xray-examples/tree/main/Shadowsocks-2022) | 已有安装流程 |
| Hysteria2 | [Hysteria2](https://github.com/XTLS/Xray-examples/tree/main/Hysteria2) | 已有安装流程 |

## 尚未加入的组合与变体

| 组合或变体 | 示例目录 |
| --- | --- |
| VLESS + TCP + TLS | [VLESS-TCP-TLS](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-TLS)、[VLESS-TCP-TLS (minimal by rprx)](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-TLS%20%28minimal%20by%20rprx%29)、[VLESS-TCP-TLS (maximal by rprx)](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-TLS%20%28maximal%20by%20rprx%29)、[VLESS-TCP-TLS-proxy protocol](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-TLS-proxy%20protocol) |
| VLESS + TCP + Vision + TLS | [VLESS-TCP-XTLS-Vision](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-XTLS-Vision) |
| VLESS + WebSocket + TLS / Nginx | [VLESS-WSS-Nginx](https://github.com/XTLS/Xray-examples/tree/main/VLESS-WSS-Nginx) |
| VLESS TCP/TLS 与 WebSocket 的回落组合 | [VLESS-TCP-TLS-WS](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP-TLS-WS) |
| VLESS + gRPC + TLS / Caddy 或 Nginx | [VLESS-GRPC](https://github.com/XTLS/Xray-examples/tree/main/VLESS-GRPC) |
| VLESS + gRPC + REALITY | [VLESS-gRPC-REALITY](https://github.com/XTLS/Xray-examples/tree/main/VLESS-gRPC-REALITY) |
| VLESS + XHTTP（SplitHTTP）+ TLS / 反向代理 / H3 | [VLESS-TLS-SplitHTTP-CaddyNginx](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TLS-SplitHTTP-CaddyNginx)、[VLESS-TLS-SplitHTTP-H3](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TLS-SplitHTTP-H3)、[VLESS-XHTTP3-Nginx](https://github.com/XTLS/Xray-examples/tree/main/VLESS-XHTTP3-Nginx) |
| VLESS + HTTP / Caddy 示例 | [VLESS-HTTP-Caddy](https://github.com/XTLS/Xray-examples/tree/main/VLESS-HTTP-Caddy) |
| VLESS + mKCPSeed 示例 | [VLESS-mKCPSeed](https://github.com/XTLS/Xray-examples/tree/main/VLESS-mKCPSeed) |
| 无 Encryption、无 TLS 的 VLESS + TCP 示例 | [VLESS-TCP](https://github.com/XTLS/Xray-examples/tree/main/VLESS-TCP) |
| SOCKS5 + TLS | [Socks5-TLS](https://github.com/XTLS/Xray-examples/tree/main/Socks5-TLS) |
| Trojan + TCP + TLS | [Trojan-TCP-TLS (minimal)](https://github.com/XTLS/Xray-examples/tree/main/Trojan-TCP-TLS%20%28minimal%29) |
| Trojan + gRPC / Caddy 或 Nginx | [Trojan-gRPC-Caddy2／Nginx](https://github.com/XTLS/Xray-examples/tree/main/Trojan-gRPC-Caddy2%EF%BC%8FNginx) |
| Shadowsocks 的 AEAD / TCP 示例 | [Shadowsocks-AEAD](https://github.com/XTLS/Xray-examples/tree/main/Shadowsocks-AEAD)、[Shadowsocks-TCP](https://github.com/XTLS/Xray-examples/tree/main/Shadowsocks-TCP) |
| VMess + TCP，及 TCP + TLS | [VMess-TCP](https://github.com/XTLS/Xray-examples/tree/main/VMess-TCP)、[VMess-TCP-TLS](https://github.com/XTLS/Xray-examples/tree/main/VMess-TCP-TLS) |
| VMess + WebSocket，及 WebSocket + TLS | [VMess-Websocket](https://github.com/XTLS/Xray-examples/tree/main/VMess-Websocket)、[VMess-Websocket-TLS](https://github.com/XTLS/Xray-examples/tree/main/VMess-Websocket-TLS) |
| VMess 的 HTTP / HTTP2 / mKCPSeed 示例 | [VMess-HTTP](https://github.com/XTLS/Xray-examples/tree/main/VMess-HTTP)、[VMess-HTTP2](https://github.com/XTLS/Xray-examples/tree/main/VMess-HTTP2)、[VMess-mKCPSeed](https://github.com/XTLS/Xray-examples/tree/main/VMess-mKCPSeed) |

本脚本的 **Encryption + XHTTP** 和 **XHTTP + REALITY** 没有提供上述 XHTTP + TLS / Nginx / Caddy / H3 部署流程，因此不能将这些示例记作已覆盖。同样，已有普通 SOCKS5 并不等于已有 SOCKS5 + TLS。

## 尚未加入的部署方案

- [All-in-One-fallbacks-Nginx](https://github.com/XTLS/Xray-examples/tree/main/All-in-One-fallbacks-Nginx)
- [ReverseProxy](https://github.com/XTLS/Xray-examples/tree/main/ReverseProxy)
- [MITM-Domain-Fronting](https://github.com/XTLS/Xray-examples/tree/main/MITM-Domain-Fronting)
- [Serverless-for-Iran](https://github.com/XTLS/Xray-examples/tree/main/Serverless-for-Iran)

这些目录涉及端口复用、反向代理或其他完整部署方案。现有 Tunnel 端口转发管理不等于已经实现 `ReverseProxy`。

## 范围说明

脚本另外提供 Encryption + REALITY、Encryption + FinalMask 等组合，不应为了匹配仓库目录重复新增已有功能。示例仓库保留了多个历史命名和方案；此处仅确认覆盖差异，不将目录存在视为已验证当前核心兼容性。后续实现仍应结合[官方全量配置文档](https://xtls.github.io/llms-full.txt)和现有核心实际验证。
