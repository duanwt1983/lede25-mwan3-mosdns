# lede25 + mwan3 + mosdns 多线负载

基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) `master` 的 **Lean 25 x86-64** 固件。  
仓库：[duanwt1983/lede25-mwan3-mosdns](https://github.com/duanwt1983/lede25-mwan3-mosdns)

- 目标：x86-64 Generic，**ext4** 根分区 **2048M**，EFI + VMDK
- Web：**luci-nginx**（不装 uhttpd）
- 防火墙：只保留 **firewall4 + nftables**（不要 iptables / legacy）
- 默认 LAN：`192.168.9.1/24`，账号 `root` / `password`

GitHub Actions 工作流显示名：`Build Lean 25 x86-64 PassWall samba4`。  
改 `.config` / `diy-*.sh` / `files/` / `package/` / `patches/` / `scripts/` 或工作流文件并推到 `main` 会触发编译；只改本 README 不会。

刷入本仓库编译的镜像即带齐下面列出的功能，**不依赖热部署**。默认账号密码只适合先装机，上线后请改掉。

## 当前固件现状（菜单）

| 位置 | 有什么 |
| --- | --- |
| 状态 → 概览 → 拓扑图 | 多 WAN / 交换机 / 终端实时速率；终端列表按设备类型显示图标（不写类型文字） |
| 状态 → 概览 → Mosdns缓存 | MosDNS 缓存查看 |
| 状态 → 概览 → 自动限速 | 按终端自动限速 |
| 状态 → 概览 → 硬件信息 | CPU / 磁盘 / SMART 等 |
| 状态 → 日志中心 | 系统日志（译成可读说明）+ 分路径存放 |
| 状态 → 系统报警 | WAN / 资源 / 安全告警开关；钉钉、PushPlus；报警日志四分类 |
| 网络 → 接口 | 含 LAN DHCP 起止、排除地址、顺序分配（写到 dnsmasq） |
| 网络 → 负载均衡 | mwan3；「自动配置」页；自带示例规则已清空 |
| 网络 → 运营商地址库 | 电信/联通/移动/其它 CIDR 日更；给 WAN 标运营商**不会**自动分流 |
| 网络 → 局域网安全 | 非法 DHCP、二级路由名单、ARP 确定性事件 |
| 网络 → 抓包分析 | 指定口抓包与简单分析 |
| 网络 → 内网测速 | LibreSpeed |
| 服务 → 网络共享 | samba4（不走 NAS 菜单） |
| 系统 → 管理权 → 远程管理 | HTTPS / 外网管理相关 |

**没有「宽带监控」菜单。** 拓扑图、硬件信息用的后台采集还在，只是不再单独开一页。

## 网络与 DNS

| 用途 | 实际做法 |
| --- | --- |
| 多线同时出网 | [dl12345 mwan3 nft](https://github.com/dl12345/mwan3)（OpenWrt 25.12 口），接口名不写死 |
| 日常 DNS | **MosDNS** 自定义 yaml（`mosdns-gen` → `/var/etc/mosdns.yaml`）。国内走 Aliyun/doh.pub，海外走 DoT `8.8.8.8`/`1.1.1.1`；`dns_leak=1` 时海外域名不回落到国内 DNS |
| DNS 跟 WAN | 两条及以上 WAN 时，国内上游 `bind_to_device`；海外上游不绑网卡，方便走 PassWall |
| 代理 | **PassWall** nft 透明代理。直连 DNS 和国外 DNS 都指向 `127.0.0.1:5335`，分流由 MosDNS 做 |
| LAN DHCP | 在 **网络 → 接口 → lan / br-lan → DHCP 服务器 → IPv4** 里按完整 IP 填起始/结束、掩码、网关、DNS、排除地址、顺序分配；租期仍在「常规设置」 |

一条线挂了：新连接、刷新网页会切到活着的线。已经走在死线上的 TCP 会断，这是策略路由的极限，不是插件没配好。

路由器上看不到完整网址（没有路径、参数），DNS / SNI 通常只能看到主机名。

首次启动：**mwan3 默认关闭**，直到在负载均衡里启用了接口再开；MosDNS 等 LuCI 里启动后再跑。

## 软件包

| 需求 | 软件包 |
| --- | --- |
| 多线 | mwan3 + luci-app-mwan3（nft） |
| DNS | mosdns + luci-app-mosdns + mosdns-mwan |
| 代理（备用） | luci-app-passwall（Xray / Sing-Box 等） |
| LAN 测速 | **LibreSpeed**（`librespeed-go`），菜单「内网测速」 |
| 终端统计/限速 | luci-app-bandix-plus + bandix-plus（eBPF，需关闭硬件 offload） |
| DDNS | ddns-go |
| 网页终端 | ttyd |
| 主题 | Argon |
| 文件共享 | samba4 |
| 磁盘管理 | luci-app-diskman + **smartmontools**（硬件信息页 SMART 健康度） |
| 文件管理 | luci-app-filemanager |

**不装**：iStore / FastNet、uhttpd、iperf3、Homebox、旧版 luci-app-ddns、SSR Plus、iptables 那一套、外网测速页、QoSmate。

## 状态概览（拓扑图）

- 多线路速率、在线设备、链路流量；单位统一 **Mbps**。
- **终端列表图标**（只在这一页的列表上，不改 Bandix 设备页、不写「小米手机」这类文字）：
  - 橙色手机：小米 / Redmi
  - 深色手机：iPhone / iPad
  - 红色手机：华为 / 荣耀（含 `HOP-AL00` 这类型号名）
  - 绿色手机：vivo / OPPO 等其它手机
  - 蓝窗格电脑：Windows（`DESKTOP-` 等）
  - 银灰电脑：macOS
  - 双天线：空主机名 + 华为网卡前缀，按无线 AP 处理
  - 镜头盒子：tilink / 萤石 `H6c_` 等录像机、摄像头
  - 灰电脑：认不出
- 判断主要靠 DHCP 主机名；没有名字且 MAC 不是随机地址时，才用网卡前缀兜底。随机 MAC 且无名的无法从 OUI 认厂。

## 系统报警

- 开关在 **状态 → 系统报警**。默认多数关闭，按需打开。
- 日志四分类：**网络 / 设备 / 安全 / 系统**。级别：**严重 / 中等 / 一般**。
- **「信息」不写入报警日志**。
- 单条 WAN 掉线 = **中等**；全部 WAN 掉线 = **严重**。
- 速率文案用 **Mbps**。客户端突发阈值 `burst_hold_sec` 的单位是**秒**（和 WAN/CPU 的「持续 N 分钟」不是同一套）。
- 推送：钉钉（安全关键词默认仍是「线路」，和日志分类无关）、PushPlus 公众号 + App。
- 可选自动维护（WAN 掉线后拉修复脚本），默认关。

## 局域网安全

菜单 **网络 → 局域网安全**（`lede-lansec`），刷入本仓库镜像即带上。

- 非法 DHCP：发现后可把该 **MAC 整机封掉**（不只是不给它发地址）。
- ARP：网关被冒充、同 IP MAC 翻转、占用已分配地址等**确定性**事件。
- 二级路由：没有可靠的自动识别（本网关单网卡接交换机时，TTL/FDB 都不够用）。靠名单 + 待确认，**不会**把手机热点/Windows 共享自动当成二级路由来封。
- MAC 在页面上统一大写；已处理过的待确认行会从列表去掉；改备注后先出现「未保存的配置」，点「保存并应用」才生效。
- 默认关闭，需要在页面里打开。

## 日志与数据盘

- 日志中心 / 报警日志：告警、MosDNS、logd 可分别指定路径。
- 若有独立分区挂到 `/data`，告警日志默认倾向 `/data/logs/alert/`。
- 编译自检会核对 overlay 里的关键脚本，避免旧热修复脚本漏装。

## 已知限制

- 策略路由切线不会把已建立的死线 TCP 救活。
- 拓扑图标不是精确设备指纹：没有主机名、随机 MAC、杂牌机都会落成灰电脑或通用图标。
- 二级路由不能靠 TTL 自动封。
- HTTPS 可信任证书（给 ddns-go 外网用）需要 DNS 服务商配合自动签发，固件里尚未做成一键。
