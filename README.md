# lede25 + mwan3 + mosdns 多线负载

基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) `master` 的 **Lean 25 x86-64** 固件。  
仓库：[duanwt1983/lede25-mwan3-mosdns](https://github.com/duanwt1983/lede25-mwan3-mosdns)

- 目标：x86-64 Generic，**ext4** 根分区 **1024M**，EFI + VMDK
- Web：**luci-nginx**（不装 uhttpd）
- 防火墙：只保留 **firewall4 + nftables**（不要 iptables / legacy）
- LAN：`192.168.9.1/24`，账号 `root` / `password`

GitHub Actions 工作流显示名保持：`Build Lean 25 x86-64 PassWall samba4`。  
改 `.config` / `diy-*.sh` / `files/` / `package/` / `patches/` / `scripts/` 或工作流文件并推到 `main` 会触发编译；只改本 README 不会。

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

## 软件

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

**不装**：iStore / FastNet、uhttpd、iperf3、Homebox、旧版 luci-app-ddns、SSR Plus、以及 iptables 那一套。

## 本仓库覆盖

- 状态概览：多线路速率、在线设备等
- 系统告警（`wanalert`）：WAN、DHCP 池、CPU、负载、内存、磁盘、温度；可选钉钉，以及 PushPlus 个人微信公众号 + App（同一条可同时发）
- 日志中心 / 报警日志：线路和资源告警单独一页；系统日志译成「发生了什么」；告警、MosDNS、logd 可分别指定存储路径
- 运营商地址库（国内源日更）：mwan3 里可选用 `isp_chinanet` / `isp_unicom` / `isp_cmcc` / `isp_other` 做目的地址规则（其它=教育网/广电/鹏博士等国内非三大运营商）；给 WAN 标注运营商**不会**自动分流；自带示例规则已清空
- LAN DHCP 排除地址写入 dnsmasq，保存接口后重载
- 局域网安全（`lede-lansec`）：非法 DHCP、二级路由名单、ARP 确定性事件；菜单「网络 → 局域网安全」。刷入本仓库编译的新固件即带上，不需要热部署

默认账号密码只适合先装机，上线后请改掉。
