# 整盘固件升级 vs 组件升级

## 机制对比

| | **组件升级**（`.tar.gz`） | **整盘固件**（`.img` / `.img.gz` + `sysupgrade`） |
|---|---------------------------|-----------------------------------------------------|
| 入口 | 系统 → 备份与更新 → **组件升级** | 系统 → 备份与更新 → **刷写固件…** |
| 镜像路径 | — | 上传到 **`/data/firmware.bin`**，刷写经 bind 为 `/tmp/firmware.bin` |
| 重启 | 一般不需要 | **必须** |

整盘能力也可通过组件包 **`lede-component-firmware-upgrade-v*.tar.gz`** 热更（刷机后需重装）。

---

## 固件升级 UX 约定（实现 checklist）

1. **「固件升级」标题**：展示当前运行版本（`/etc/openwrt_release` → `R… · OpenWrt … · target`）。
2. **已有 `/data/firmware.bin`**：不自动刷写 →「使用此固件包 / 删除 / 取消」。
3. **上传**：进度**只在弹窗顶部状态栏**；日志不写上传百分比。
4. **上传完成后**：日志立即写「上传完成 → 进入校验…」；校验 / `--test` 长耗时阶段每 **~10 秒**一行阶段日志（非 logread 内核垃圾）。
5. **校验通过后**：必须点 **「确认刷写并重启」** 才 `sysupgrade`。
6. **刷写中**：轮询 `lede-firmware-progress.sh`（dd / 日志）；**LuCI 会在写盘时断线**，浏览器里**看不到** stage2 的「3 秒后 reboot」（该条在路由器日志与 `/data/lede-fw-flash.log`）；断线后页面应**自动重连**当前 IP（如 192.168.9.1）。
7. **刷写后重启**：`do_stage2` 提示 **3 秒后 reboot** 后 `sync; reboot -f`；**不** `umount -a`（避免 `/data`/bind 挂载卡死）；stage2 **不用 logger**。
   - **整盘刷机后** rootfs 会回到镜像自带的 stock `do_stage2`（含 `umount -a`）→ 表现为 **dd 可能已跑完但一直不重启**。必须先 **组件 v1.0.8+ / deploy 脚本** 或 **6.80 带 overlay 的新镜像**，再刷下一次。
   - 成功标志：重启后 `/etc/lede-fw-last-flash-success`；刷写前会有 `/data/.lede-fw-flash-pending`。
8. **刷写成功重启后**：`46-lede-firmware-cleanup` 删除 `/data/firmware.bin`，写入 `/etc/lede-fw-last-flash-success`；再次打开弹窗可见「上次刷写记录」。

---

## 大文件上传依赖（overlay / 组件包）

统一脚本：**`/usr/libexec/lede-firmware-upload-env.sh`**（`45-nginx-firmware-upload`、`lede-cgi-tmp` 均调用它）

| 问题 | 处理 |
|------|------|
| nginx 128M / 413 | 全局与 cgi-upload `client_max_body_size 0` |
| nginx 落盘占满 root | `client_body_temp_path /data/nginx-body` |
| cgi-io 写 `/tmp` tmpfs 满 | 上传前由 **`upload-env.sh`** 临时：`mkdir -p /dat` + `bind /data/cgi-tmp → /dat`（cgi-io 二进制里路径为 4 字节的 `/dat`，不是 `/data`）；**平时不挂载**，删除固件/刷机成功 **`upload-teardown.sh` 会 umount** |
| uwsgi 上传到一半断连 | **`reload-on-as` / `reload-on-rss` 设为 0**，`harakiri=7200`，`limit-as=8192` |
| 上传 HTTP 失败但已落盘 | LuCI 按 `/data/firmware.bin` 大小自动恢复继续校验 |

自检：`/usr/libexec/lede-firmware-upload-check.sh`（`fail=0` 再传 2GB）。空闲时 **`OK: /dat upload bind idle` 是正常**，不是故障；上传/校验前 LuCI 会先跑 **`upload-env.sh`** 再检查。

刷机后 **`47` 只恢复 `do_stage2`**，**不会**开机挂载 `/dat`；`lede-cgi-tmp` **禁止 enable**。打开 LuCI 刷写/上传前由 `upload-env.sh` 按需准备环境。

**注意：** 上传过程中不要执行会 `uwsgi restart` / `nginx reload` 的部署脚本，否则会出现「upstream closed」误报失败。

---

## 部署与打包

| 场景 | 命令 |
|------|------|
| 测试机热更（如 9.1） | `./scripts/dev/deploy-flash-firmware-ui-91.sh [ip] [password]` |
| 打组件包 | `./scripts/build-lede-component-pack.sh firmware-upgrade` → `dist/lede-component-firmware-upgrade-v*.tar.gz` |
| 进镜像 | `files/` + `diy-part2.sh` overlay 自检 |

---

## 保留配置

弹窗内 **「保留当前配置」** 默认勾选 → `sysupgrade` 不带 `-n`；取消则 `-n` 清空配置。
