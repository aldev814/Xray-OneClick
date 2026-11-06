# Changelog

## Unreleased
- **终端菜单整理**：主菜单收拢为 9 个功能入口，协议安装按用途分组并标记已配置项；补齐服务诊断、分享链接、迁移预览及脚本更新入口，同步菜单文档和协议覆盖清单。
- **官方文档字段同步**：VLESS/Hysteria/SOCKS 用户列表使用 `users`；Tunnel 使用 `rewriteAddress/rewritePort/allowedNetwork`；FinalMask 分片使用 `lengths/delays` 数组；识别 `V6Only` 并移除 REALITY 服务端的 `spiderX`。查看、导出、密钥重置兼容旧字段，`ike migrate` 同步转换配置和 FinalMask state。
- **诊断报告脱敏**：报告中的分享链接统一脱敏，补齐 SOCKS5 URI 识别。
- **链式代理目标保留**：所有 VLESS 入站的嗅探增加 `routeOnly: true`，避免将内层 TLS/REALITY 的 SNI 覆盖为实际连接目标；`ike migrate` 可为已启用嗅探的本脚本 VLESS 入站补齐该设置。
- **迁移完整性**：缺少 REALITY target/dest 时中止迁移并保留原配置，避免 jq 的 `empty` 静默删除入站；迁移后校验配置，失败恢复 config/state。
- **分享链接准确性**：导出使用公网探测，所有协议支持双栈导出并遵循自定义入口和外部端口；隔离菜单残留参数，编码 SOCKS 凭据，停止回退到地址可能过期的缓存链接。
- **监听识别**：按当前配置识别通配监听与 `v6only`，避免历史 state 将双栈入站误判为仅 IPv4。

## 1.1.31
- **自升级一致性**：解析目标 commit SHA 后，从同一提交下载版本、入口与模块；按目标入口的模块清单部署，支持新增/删除模块，并在替换前验证完整加载，记录部署 `COMMIT`。
- **操作互斥**：菜单及会修改配置/state 的 CLI 共用操作锁，正常退出或 INT/TERM 时释放；纯版本、服务状态等查询仍可并行。
- **精确回滚**：配置备份同时保存配套 state，失败优先恢复本次操作的明确快照，避免误用时间更新的无关备份；快照丢失时停止恢复。
- **文档与测试**：修正帮助中的 cnblock 默认值；增加升级失败注入、目标模块变更、精确快照和并发锁行为测试。

## 1.1.30
- **64MB 极限低内存容器支持**：
  - **避开 `tmpfs` 内存盘**：下载临时目录在检测到 `/tmp` 处于 tmpfs 挂载或指定变量时，自动回退到真正的磁盘路径 `/var/tmp`，防止压缩包直接挤占容器 RAM。
  - **按需解压与即解即删**：移除冗余的 `unzip -t`，仅按需解压核心二进制与 geo 数据，解压完成后立即删除 25MB+ 压缩包并冲刷磁盘缓存（`sync`），杜绝压缩包与解压文件同时驻留内存。
  - **单副本移动**：geo 规则文件放置由 `cp` 改为 `mv`，避免在临时目录与目标目录各保留一份副本。
  - **Go 运行时低内存调优**：在 OpenRC 与 Systemd 服务中注入 `GOMEMLIMIT=35MiB`、`GOGC=30` 与 `GODEBUG=madvdontneed=1`，确保 Xray 守护进程在 64MB 极小内存下稳定运行不崩溃。
  - **恢复中国大陆直连屏蔽默认关闭（`cnblock: off`）**：不再在 `init_config` 中默认启用 cnblock（enhanced），避免加载数万条域名规则（`geosite:cn`）常驻占用 ~20MB 堆内存，用户仍可按需通过 `ike cnblock basic|enhanced` 手动开启。

## 1.1.29
- **Hysteria2 自签证书指纹**：安装、查看、`ike view` 和脱敏报告现在显示 `pinnedPeerCertSha256`，可直接填入客户端 TLS 配置；现有 Hysteria2 分享 URI 保持不变。

## 1.1.28
- **彻底防止安装混版**：bootstrap 先通过 GitHub API 将分支解析为固定 commit SHA，再从同一提交下载 `install.sh` 与全部 `lib/` 模块，避免分支更新及 CDN 缓存导致版本号与功能模块不一致。
- **修复全新安装提前重启服务**：默认安全规则初始化改为直接写配置，不再经过会调用 `apply_config` 的交互设置入口，确保 OpenRC/systemd 服务创建前不会尝试重启。

## 1.1.27
- **修复重装回退旧版本**：bootstrap 改用独立临时目录并在退出时整体清理，避免旧版模块残留在共享 `/tmp/lib`，导致后续安装显示远端新版本却实际加载旧模块。
- **卸载清理安装器残留**：完整卸载同时清理 `ike.old.*`、`ike.upgrade.new.*`，并在确认项目标识后删除旧 `/tmp/lib` 中的已知模块；混入的非项目文件会保留。

## 1.1.26
- **修复 `ike upgrade` 必然交换失败**：暂存目录改到 `/usr/local/share/ike` 的同级路径，避免部署目录改名时暂存目录被一起移动，导致后续 `mv` 找不到源目录。
- **单文件安装防 CDN 混版**：`install.sh` 下载 `lib/*.sh` 时增加统一时间戳查询参数，避免 GitHub Raw 缓存返回旧模块。

## 1.1.25
- **`ike upgrade` 加固**：下载 URL 增加时间戳查询参数穿透 raw.githubusercontent.com 的 CDN 缓存；替换部署目录前校验暂存 `01-constants.sh` 的 `SCRIPT_VERSION` 与远程 `VERSION` 一致，不一致即中止，避免 CDN 缓存导致新旧文件混合部署成「混版」（版本号显示新、部分模块仍是旧）的故障。

## 1.1.24
- **脚本自升级**：新增 `ike upgrade [--force]`，从 `${IKE_REPOSITORY}@${IKE_REF}` 拉取远程 `VERSION` 比对后，下载最新 `install.sh` 与全部 `lib/` 模块到暂存目录，逐个 `bash -n` 语法校验通过才原子替换部署目录（`/usr/local/share/ike`）；任一步失败保持原版本不动。`--force` 可在版本相同时强制重新部署。同时修复 1.1.23 中菜单 18/19 默认开启逻辑的无限递归（刷屏后静默失败）与全新安装时服务未创建即重启失败的隐患，默认开启不再覆盖用户手动关闭（`enhanced_block_user_set` / `cnblock_user_set` 状态标记）。

## 1.1.23
- **合并上游 ike-sh 全量审计修复**（含 `minClientVer: 0.0.0` Reality 兼容、事务/原子写入、公网 Endpoint 探测、供应链 digest 校验、Docker 测试套件等），并保留本仓库魔改特性（`ike export links` 直接输出分享 URI、菜单 18/19 默认开启、cnblock 默认 enhanced、fp=firefox、仓库地址 aldev814）。详细见下方 1.1.22 两段。

## 1.1.22（本仓库魔改特性）
- **导出分享链接**：新增 `ike export links` / `ike links`，仅输出已安装协议的分享 URI（一行一条，便于直接导入客户端）；支持 `ipv4|ipv6|dual` 与 `--output PATH`。
- 基础 VLESS Encryption 补齐 `build_vless_enc_share_link`，并写入 state 的 `link` 字段；`ike view` 复用该 builder。
- Reality / 高级 Reality 组合分享链接与手动参数中的 `fp` / Fingerprint 默认改为 `firefox`。
- 仓库地址统一为 `aldev814/Xray-OneClick`（constants、install、bootstrap、tunnel 部署包、README、发布文档）。
- **菜单 18/19 默认开启**：`init_config` 时默认启用增强安全屏蔽（菜单 19）与大陆直连屏蔽增强模式（菜单 18，cnblock 默认 enhanced）；遵循用户已设状态，手动关闭后不强制覆盖。

## 1.1.22 - 2026-08-12（上游 ike-sh 审计）

- **第二轮全量审计**：修复 `migrate --dry-run` 实际写盘、迁移半成功不回滚、同秒备份覆盖、未知 CLI 子命令返回成功、`service repair` 吞掉失败、配置编辑校验/重启失败不恢复等控制流问题。
- **事务与原子写入**：协议安装/删除、Tunnel 状态同步、密钥重置和 Xray 二进制升级均补齐 config/state/服务回滚；配置与 state 临时文件改为在目标目录内创建，避免跨文件系统 `mv` 失去原子性。
- **安装与卸载安全**：模块下载先写临时文件并通过 Bash 语法校验后再提交；systemd/OpenRC 文件原子生成；卸载拒绝根目录和系统级宽目录，purge 备份失败会中止删除，`--keep-config` 仍会清理程序与资源目录。
- **Endpoint 与 IPv6 修复**：自定义 Endpoint 增加主机、IPv6 和端口范围校验；本机 IPv6 探测会跳过 ULA/保留地址并继续选择真正的公网地址，避免首个 `scope global` 地址误判。
- **Docker 测试增强**：增加迁移只读/回滚、唯一备份、安全删除、二进制回滚、Endpoint 边界、CLI 失败传播和密钥重置事务测试；完整套件提升为 warning 级 ShellCheck（仅排除跨模块变量/可选参数误报）。
- **REALITY 客户端兼容性**：普通 Reality 与全部高级 Reality 组合生成的 `realitySettings` 显式加入 `"minClientVer": "0.0.0"`，避免新版 Xray-core 的默认最低客户端版本限制拒绝旧客户端；配置生成测试同步覆盖该字段。
- **快捷命令冲突修复**：移除历史兼容快捷命令及其安装、卸载、菜单、测试和文档遗留；安装器现在只创建 `ike` 命令，避免覆盖其他代理项目的同名入口。
- **公网 Endpoint 修复**：`ike view`、协议详情与客户端导出不再使用 `hostname -I` 的私网地址生成分享链接；改为并发直连多个探测源、严格过滤私网/保留地址、仅在本机存在公网 IPv6 时探测 IPv6，并复用单次探测结果。代理环境使用 `curl --noproxy '*'`，避免误取代理出口；探测失败时提示使用 `ike endpoint set`，不再静默回退到内网 IP。
- **Xray prerelease / 供应链修复**：修复 prerelease release JSON 被重复按数组解析导致下载失败；保留解析后的真实版本信息，并使用 GitHub release asset 的 `sha256:` digest 校验下载包。旧 release 未提供 digest 时会明确提示跳过。
- **事务与回滚修复**：基础 VLESS Encryption 对 backup/mktemp/jq/mv/state 全链路检查，配置应用成功后才提交 state；Hysteria2 删除失败时保留证书，避免回滚后的 inbound 引用已删除文件。
- **安装一致性与测试**：bootstrap 将 `install.sh` 与 `lib/` 固定到同一个 repository/ref，并在成功执行后清理临时安装器；新增公网 IP、prerelease、摘要校验、报告脱敏、Hysteria2 删除、VLESS 状态顺序、Tunnel 导出唯一性及安装入口回归测试。新增固定版本 Xray 的 Docker 测试镜像，CI 在容器内执行模块/版本检查、全部 Shell 语法与 warning 级 ShellCheck、回归测试及真实配置校验。

## 1.1.21
- **健壮性修复（SOCKS5）**：`install_socks5` / `state_set_socks5` 由 `jq … >tmp && mv` 精简写法改为全仓一致的严谨写法（jq 失败即 `rm tmp` + 报错 + `return 1`），并为 `backup_config`/`mktemp` 补失败判断，杜绝 jq 静默失败却误报「安装完成」。
- **健壮性修复（CLI 参数解析）**：取值类 `--flag` 作为命令末尾且缺省值时，`shift 2` 在剩余参数 <2 时不位移，导致 `while` 解析循环死循环；`lib/74-cli-protocols.sh` 与 `lib/90-test-harness.sh` 解析循环中的 `shift 2` 统一改为 `shift; shift`（≥2 个参数时等价，缺值时干净退出并回落到交互/默认值）。
- 完成全仓逐文件 BUG 走查（含 `lib/56-tunnel.sh` 2451 行端到端核对），未发现新的中/高危问题。

## 1.1.20
- **关键修复（Alpine 安装失败）**：`detect_arch` 之前在 Alpine 上拼接 `-musl` 后缀下载 `Xray-linux-64-musl.zip`，但官方 XTLS/Xray-core 不发布 `-musl` 包（Linux 为 `CGO_ENABLED=0` 静态 Go 二进制，musl/glibc 通用），导致 Alpine 资产 404 安装失败；现统一使用官方标准包（如 `Xray-linux-64.zip`），并移除多余的 `alpine_uses_musl_asset` 门禁。
- README/注释同步：去除「下载 musl 版 Xray 包」表述，改为说明静态二进制兼容 musl。

## 1.1.19
- **Alpine 全链路修复**：`scripts/bootstrap.sh` 重写为 POSIX `sh`，全新 Alpine 无需预装 bash/sudo（自动 `apk add bash`/`curl` 后再用 bash 运行安装器），支持 curl 或 wget，非 root 兼容 doas/无 sudo 提示。
- `preflight_arch` 放行 `detect_arch` 已支持的 arm32(armv7/armv6/armv5)/riscv64/i386 架构，少见架构降级 warn，消除 Alpine ARM32 误报「不支持架构」。
- OpenRC init 依赖 `need net` → `use net` + `after net firewall`，避免无 net 服务的容器/LXC 无法启动或开机自启失败。
- 修正 `lib/01-constants.sh` `SCRIPT_VERSION`（此前停在 1.1.17 未随 1.1.18 同步，导致 `ike version` 与 `VERSION` 不一致，CI 版本一致性校验会失败）。
- README 文档漂移修正：卸载子菜单更新为实际 14 项；修正高级组合(9/10/11)、SOCKS5(12)、Tunnel(21)、显示模式(15)、卸载入口(17) 等菜单项号。

## 1.1.18
- VLESS Encryption（含 +FinalMask / +XHTTP / 高级组合）在生成密钥前新增 `ensure_xray_vlessenc` 自愈：确保 Xray 已安装且支持 `vlessenc`，过旧则自动强制升级并复验，修复 `xray vlessenc` 执行失败导致安装中断。
- 「重置密钥/密码」(菜单第 16 项) 扩展覆盖全部 VLESS 与 REALITY 系列协议（REALITY 轮换密钥对，老客户端需重新导入链接）。
- `migrate_old_state` 补全 `vless_enc_finalmask` / `vless_enc_xhttp` 的 `listen_scope` 回填。
- 移除 6 个孤立未调用函数；新增 `.gitattributes` 强制 LF 行尾。

## 1.1.17
- 新增协议「Hysteria2」(QUIC/TLS,自签证书 + Salamander obfs):菜单第 13 项与 CLI `ike hysteria2 install|show|remove`(`--port/--sni/--dry-run`);自动生成自签证书、认证密码与 obfs 密码,分享链接含 `insecure=1`。需 Xray-core v26+。
- FinalMask sudoku 现生成随机 `password`(双端共享密钥,经 `fm` 链接下发),修正原裸 `{type:sudoku}` 无密钥、外观可预测的问题。
- REALITY 端口提示优先推荐 443(Xray 官方警告:非 443 端口 + 借用 SNI 更易被探测封锁),选择非 443 时给出提示。
- 主菜单顺序微调:6/7 改为「VLESS Encryption + XHTTP」在前、「+ FinalMask」在后。

## 1.1.16
- 新增协议「VLESS Encryption + XHTTP」(纯净,不含 FinalMask/REALITY):菜单第 7 项与 CLI `ike enc-xhttp install|show|remove`(支持 `--port/--path/--auth/--dry-run`);生成 `protocol:vless / network:xhttp / security:none` 的加密入站,接入 view 链接、导出摘要、卸载菜单与离线配置生成测试。

## 1.1.15
- 新增协议「VLESS Encryption + FinalMask（sudoku，TCP）」：菜单第 7 项与 CLI `ike enc-finalmask install|show|remove`；生成 `streamSettings.finalmask = {tcp:[{type:"sudoku"}]}` 的 VLESS 加密 TCP 入站（`security:none`），并接入 view 链接、导出摘要、卸载菜单与离线配置生成测试。FinalMask(sudoku) 需较新 Xray-core 支持。

## 1.1.14
- 修复 `scripts/bootstrap.sh`：提取版本号时 grep 在 `install.sh` 中找不到 `SCRIPT_VERSION`（已移至 `lib/01-constants.sh`），叠加 `set -euo pipefail` 导致命令替换失败、一键安装在打印「下载…」后静默退出；改为容错（失败不中断）并回退到 `lib/01-constants.sh` 获取版本
- 修复 `curl ... | sudo bash` 管道方式下 stdin 被占用、交互菜单及所有 `read` 立即 EOF 空转退出：`install.sh` 进入交互逻辑前若检测到非 tty 且 `/dev/tty` 可读则 `exec </dev/tty`

## 1.1.13
- 版本号单一来源：`VERSION` + `SCRIPT_VERSION` + README 去重；CI 校验三者一致
- 修复 README 标题与「当前版本」不同步（1.1.12 vs 1.1.11）

## 1.1.12
- OpenRC 审查修复：musl 仅用于有官方包的架构；去掉 `after firewall`；init 增加 `directory` 指向 geo 资源目录
- `prepare_system` / `ike doctor` 补 `check_os`+`detect_arch`；卸载/导出/日志路径统一 OpenRC 分支
- Alpine 仅在缺少 `rc-service` 时安装 openrc 包

## 1.1.11
- **Alpine / OpenRC**：预检、doctor、服务写入与日志路径完整支持；Alpine 自动选用 musl 版 Xray 包
- 新增 `scripts/bootstrap.sh` 一行安装（`curl ... | sudo bash`）
- OpenRC init 脚本增强：日志目录、`start_pre`、覆盖前备份

## 1.1.10
- 修复 P0 模块化遗漏：恢复 `init_state` / `state_set_meta_action` 等 5 个 state 函数至 `lib/22-state.sh`
- 修复 `ike_ensure_lib_modules` 早退导致旧 `lib/` 无法增量更新
- P1 整理：Endpoint CLI 归位 `40-network.sh`，`xray_service_status` 归位 `31-service.sh`；bootstrap 加载顺序优化

## 1.1.9
- P6 模块化：`install_shortcut` 拆至 `lib/03-installer.sh`，`install.sh` 主入口约 216 行；README 补充模块表与安装说明

## 1.1.8
- P5 模块化：系统准备与预检拆至 `lib/03-system.sh`，`env_truthy` 上移至 `02-output.sh`；主入口约 200 行
- P0–P4 模块化：`install.sh` 拆分为 31 个 `lib/` 模块；修复 P3 误删的 `run_xray_command` / `migrate_old_state` 与 `run_logs_command` 损坏；README 补充 `lib/` 架构说明
- P0–P3 模块化：基础设施、协议、Tunnel、view/menu、诊断导出；安装时同步复制 `lib/`；curl 单文件安装时自动从 GitHub 拉取全部 lib 模块
- CI 增加全量 lib 完整性检查、shellcheck、`install.sh version` 冒烟测试
- 修复交互式卸载 SS2022 / VLESS Encryption / SOCKS5 时未备份、先删 state 导致 config/state 不一致的问题
- 修复 Tunnel 部署包 `install-tunnels.sh` 误进入交互菜单，改为非交互 bootstrap
- `ike config edit` 编辑前自动备份 config.json
- 新增 GitHub Actions CI，运行离线配置生成测试

## 1.1.7
- 新增 Xray stable/prerelease 通道
- REALITY 生成字段迁移为 `target`，旧配置仍兼容读取
- 高级 Reality 组合增加 `fallback-limit` 与 target 风险提示
- FinalMask 默认策略收紧为更保守的 off，开启后默认 balanced
- 新增离线配置生成测试，覆盖 Reality、XHTTP、FinalMask、高级组合和 fallback-limit
- 更新 README 与诊断输出
