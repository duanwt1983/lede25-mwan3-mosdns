# 编译方式说明（GitHub 与编译机）

本仓库是 **LEDE overlay**（`files/`、`patches/`、`diy-part*.sh` 等）。**进固件的内容** 只取决于 overlay；**在哪编译** 决定是增量还是每次从零开始。

---

## 为什么不在 GitHub 上做日常编译

GitHub Actions 每次运行都在 **全新的 `ubuntu-24.04` 虚拟机** 上：

- 没有保留上一次的 `openwrt/`、`build_dir/`、`staging_dir/`、`dl/`（除非自己接 cache，本仓库未采用）
- 只能 **重新 clone LEDE → feeds → 全量 download → 全量 make**（数小时级）
- **无法** 做与 6.80 相同的 **增量编译**（改几个 LuCI 文件只重编少数包）

因此：**GitHub 只作源码托管与备份**；改 overlay 后请在 **自有编译机** 上增量出固件。

---

## 1. 编译机（推荐，如 192.168.6.80）

在 `/openwrt-build` 等目录 **长期保留** 一棵 `openwrt` 树，overlay 更新后增量 `make`。

| 脚本 | 用途 |
|------|------|
| `scripts/setup-ubuntu24-build-host.sh` | 编译机一次性装依赖（需 sudo） |
| `scripts/build-incremental.sh` | **增量**：更新 `files/`、`.config`、`diy-part2.sh` 后 `make` |
| `scripts/build-offline.sh` | **全量**：删树重 clone（仅首编或大改 toolchain 时用） |
| `scripts/deploy-remote-build.sh` | 从开发机 rsync overlay 到远程（全量，前台跟日志） |
| `scripts/trigger-remote-incremental.sh` | rsync overlay 后在远程 **后台** 跑增量编译（不跟日志） |

```bash
export LEDE_WORK=/openwrt-build
export OVERLAY=$LEDE_WORK/overlay
bash "$OVERLAY/scripts/build-incremental.sh"
```

在 Mac 上推源码并 **后台** 开编（不占用终端跟日志）：

```bash
cp scripts/build-host-680.env.example scripts/build-host-680.env   # BUILD_HOST、SSHPASS
./scripts/build-680-all.sh
# 或：./scripts/trigger-remote-incremental.sh dwt@192.168.6.80
# 编译机上查看：tail -f /openwrt-build/incremental-*.log
```

产物：`$LEDE_WORK/openwrt/bin/targets/x86/64/`。

### 增量 vs 全量（编译机）

| | **增量** `build-incremental.sh` | **全量** `build-offline.sh` |
|---|--------------------------------|-----------------------------|
| 何时用 | **日常**：改 overlay / LuCI / 组件 | **首编**、删树后、或 upstream LEDE **大版本 / toolchain** 变动 |
| 是否重 clone | 否，沿用 `$LEDE_WORK/openwrt` | 默认 `rm -rf openwrt` 再 clone |
| 是否重 download | 一般否（保留 `dl/`） | 可 `SKIP_DOWNLOAD=1` 保留 `dl/` |
| 编出来的固件 | 与全量相同类型的 **sysupgrade / combined** 镜像 | 同上 |

**和路由器升级的关系：** 编译方式只影响 **6.80 上怎么出包**，不影响 **9.1 能否升级**。只要新镜像是同一 **target**（如 `x86/64`）、用 LuCI **刷写固件**（默认 **保留配置**），**增量编出的固件** 和 **全量编出的固件** 都可以在当前系统上升级。大版本升级后若个别 kmod 不匹配，再按需重装对应 ipk 或 `-n` 清空配置刷机。

清理编译机磁盘（保留 openwrt 树以便继续增量）：

```bash
bash /openwrt-build/overlay/scripts/cleanup-build-host.sh
# 需要更多空间：AGGRESSIVE=1 bash .../cleanup-build-host.sh
```

---

## 2. GitHub Actions（遗留 / 仅手动发版）

- 工作流：`.github/workflows/build-lede.yml`
- **`main` push** 与 **Actions → Run workflow** 均会触发（GitHub 上为 **全量** 编译，数小时）
- 日常改 LuCI/组件仍推荐 **6.80 增量**（`scripts/build-680-all.sh`），勿依赖 GitHub 做迭代编

---

## 3. 共同部分

1. `files/` overlay  
2. `patches/*/apply.sh` + `diy-part2.sh`  
3. `package/` 本地 feed  

组件热更新见 [COMPONENT-PACK-DEVELOPMENT.md](COMPONENT-PACK-DEVELOPMENT.md)。

### 区域接入中心（frpc）

下文链接中的 `center.example.com` 仅为文档示例；**固件 UCI / frpc 默认中心域名为 `center.123.gd.cn`**（见 `files/etc/config/lede-center`），与线上 Authelia、frps 一致。

固件内置 `lede-center-frpc`（frp **0.61.1**，与总部 frps 一致）。LuCI 在 **系统 → 管理权 → 远程管理** 页内选项卡 **区域接入中心**（与本机外网管理并列）。每台网关填写唯一 **站点 ID**、**remote_port_luci**（在 6.251 登记）和 **frps token** 后保存即可出站连 `center.example.com:18007`；保存并应用时会同步 frpc 配置，并为「内网 TCP 隧道」在防火墙放行网关到 LAN 的访问（不在门店 WAN 开放中心端口）。配置保留见 `lib/upgrade/keep.d/lede-center`。

### 总部中心门户（6.251）

源码目录 `center-portal/`：站点登记、`sites.json`、Nginx/OpenResty Lua（`/home/gw/<site_id>/…` 反代 LuCI）。部署：

```bash
cp scripts/center-portal-251.env.example scripts/center-portal-251.env   # 填写 SSHPASS，勿提交
./scripts/deploy-center-portal-251.sh root@192.168.6.251
```

外网入口 LEDE 仅需转发 **18443**、**18007** 到 6.251。LuCI 推荐链接（需 Authelia，**不**依赖内网隧道 19100 等公网口）：

`https://center.example.com:18443/home/gw/<site_id>/cgi-bin/luci/`

内网 TCP 隧道端口（19100–19999）若要从公网访问，须在入口 LEDE 逐端口转发到 6.251。

---

## 4. 同步源码到 GitHub

```bash
./scripts/sync-to-github.sh
```

- 只同步 overlay / 文档，**不会** 启动 Actions 编译（工作流无 push 触发）
- 日常开发：**6.80 增量编固件 → 需要时再 push 源码**
