# 编译方式说明（GitHub 与编译机）

本仓库是 **LEDE overlay**（`files/`、`patches/`、`diy-part*.sh` 等）。**进固件的内容** 只取决于 overlay；**在哪编译** 决定是增量还是每次从零开始。

---

## 为什么不在 GitHub 上做日常编译

GitHub Actions 每次运行都在 **全新的 `ubuntu-24.04` 虚拟机** 上：

- 没有保留上一次的 `openwrt/`、`build_dir/`、`staging_dir/`、`dl/`（除非自己接 cache，本仓库未采用）
- 只能 **重新 clone LEDE → feeds → 全量 download → 全量 make**（数小时级）
- **无法** 做与 6.80 相同的 **增量编译**（改几个 LuCI 文件只重编少数包）

因此：**GitHub Actions 专门做全量出固件/Release**；日常快速迭代请在 **自有编译机（6.80）** 上增量出包。

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

## 2. GitHub Actions（全量编译 / 发 Release）

- 工作流：`.github/workflows/build-lede.yml`
- 每次均在 **全新 Ubuntu 虚拟机** 上：**clone LEDE → feeds → download → 全量 make**（无增量缓存）
- **`main` push** 与 **Actions → Run workflow** 均会触发，通常 **2–3 小时**，成功后上传固件与 Release
- 与 6.80 增量并行：GitHub 负责 **全量镜像**；本地改 LuCI/组件验证用 **`scripts/build-680-all.sh`**

---

## 3. 共同部分

1. `files/` overlay  
2. `patches/*/apply.sh` + `diy-part2.sh`  
3. `package/` 本地 feed  

组件热更新见 [COMPONENT-PACK-DEVELOPMENT.md](COMPONENT-PACK-DEVELOPMENT.md)。

### 区域接入中心（frpc）

下文链接中的 `center.example.com` 仅为文档示例；**固件 UCI / frpc 默认中心域名为 `center.123.gd.cn`**（见 `files/etc/config/lede-center`），与线上 Authelia、frps 一致。

固件内置 `lede-center-frpc`（frp **0.71.0**，须与总部 frps 同版本）。LuCI 在 **系统 → 管理权 → 远程管理** 页内选项卡 **区域接入中心**（与本机外网管理并列）。每台网关须先 **导入中心 CA**（LuCI 一键下载或 `/etc/lede-center/frps-ca.crt`），**强制 TLS 校验**，无 CA 则无法生成配置/连接 `center.example.com:18007`。填写 **站点 ID**、**remote_port_luci**（在 6.251 登记）和 **frps token** 后保存并应用；会 `frpc verify` 并同步 frpc 配置。配置保留见 `lib/upgrade/keep.d/lede-center`。

### 总部中心门户（6.251）

源码目录 `center-portal/`：站点登记、`sites.json`、Nginx/OpenResty Lua（`/home/gw/<site_id>/…` 反代 LuCI）。部署：

```bash
cp scripts/center-portal-251.env.example scripts/center-portal-251.env   # 填写 SSHPASS，勿提交
./scripts/deploy-center-portal-251.sh root@192.168.6.251
```

中心机升级 frps（与固件 frpc 对齐）：`center-portal-upgrade-frps`（脚本在 `center-portal/scripts/`，deploy 时安装到 `/opt/center-portal/`）。Dashboard 默认 `127.0.0.1:7500`，门户 `center-portal-status` 走 **API v2** 展示客户端/代理/流量；可选 `enablePrometheus = true`（见 `center-portal/config/frps.toml.example`）。

外网入口 LEDE 仅需转发 **18443**、**18007** 到 6.251。LuCI 推荐链接（需 Authelia，**不**依赖内网隧道 19100 等公网口）：

`https://center.example.com:18443/home/gw/<site_id>/cgi-bin/luci/`

内网 TCP 隧道端口（19100–19999）若要从公网访问，须在入口 LEDE 逐端口转发到 6.251。

---

## 4. 同步源码到 GitHub

```bash
./scripts/sync-to-github.sh
```

- **`main` push 会自动排队全量编译**；若只想备份源码、暂不编，可推其它分支或临时关闭 workflow
- 推荐节奏：**6.80 增量验证** → 满意后 **push `main`** 触发 GitHub 全量出 Release 固件
