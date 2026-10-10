# 整盘固件升级 vs 组件升级

## 机制对比

| | **组件升级**（`.tar.gz`） | **整盘固件**（`.img` / `.img.gz` + `sysupgrade`） |
|---|---------------------------|-----------------------------------------------------|
| 入口 | 系统 → 备份与更新 → **组件升级** | 系统 → 备份与更新 → **刷写固件…** |
| 镜像路径 | — | 上传到 **`/data/firmware.bin`**，刷写经 bind 为 `/tmp/firmware.bin` |
| 重启 | 一般不需要 | **必须** |

整盘能力也可通过组件包 **`lede-component-firmware-upgrade-v*.tar.gz`** 热更（刷机后需重装）。

### 旧固件上手动装组件包（无「组件升级」菜单）

1. 将 `dist/lede-component-firmware-upgrade-v*.tar.gz` 拷到路由器，用 `lede-component-apply file …` 安装（包内自带 `lede-component-apply` 时可先解出该脚本再执行）。
2. **v1.0.21+** 安装后会跑 **`lede-firmware-bootstrap.sh`**：挂载/启用 `/data`、`nginx`/`uwsgi` 模板、恢复 LEDE `do_stage2`、按需 **reload rpcd**（加载刷机 ACL）。
3. 若仍失败，SSH 自检：

   ```sh
   /usr/libexec/lede-firmware-bootstrap.sh
   /usr/libexec/lede-firmware-upload-check.sh   # 需 SUMMARY fail=0
   tail -50 /tmp/lede-firmware-bootstrap.log
   ```

4. **`/data` 无独立分区**（仅 overlay 目录）：小镜像可能可用；**≥2GB 整盘镜像** 需先 **`lede-data-setup`** 或刷入带 LEDEDATA 的新镜像。

**v1.0.20 及更早**：`post-apply` 在 `/data` 未挂载时会因 `upload-env` 失败而**中途退出**，nginx/ACL 可能未配全 → 请升级到 **v1.0.21+** 或手动执行 bootstrap。

**上传/写盘立刻失败（日志实锤）**：`logread` / nginx error 出现  
`POST /cgi-bin/cgi-upload` + `connect() to unix://.../luci-cgi_io.socket failed (111: Connection refused)`  
原因是 **`lede-firmware-bootstrap.sh` 在上传前 `uwsgi restart`**，与正在进行的固件 POST 冲突。请 **v1.0.24+**（`quick` 模式不再 restart uwsgi；LuCI 不再默认跑 `full` bootstrap）。

**刷写 sysupgrade 失败**：见 v1.0.23 `lede-firmware-flash.sh` 与 rpcd ACL 整行匹配。

---

## 固件升级 UX 约定（实现 checklist）

1. **「固件升级」标题**：展示当前运行版本（`/etc/openwrt_release` → `R… · OpenWrt … · target`）。
2. **已有 `/data/firmware.bin`**：不自动刷写 →「使用此固件包 / 删除 / 取消」。
3. **上传**：进度**只在弹窗顶部状态栏**；日志不写上传百分比。
4. **上传完成后**：日志立即写「上传完成 → 进入校验…」；校验 / `--test` 长耗时阶段每 **~10 秒**一行阶段日志（非 logread 内核垃圾）。
5. **校验通过后**：必须点 **「确认刷写并重启」** 才 `sysupgrade`。
6. **刷写中**：轮询 `lede-firmware-progress.sh`（dd / 日志）；**LuCI 会在写盘时断线**，浏览器里**看不到** stage2 的「3 秒后 reboot」（该条在路由器日志与 `/data/lede-fw-flash.log`）；断线后状态栏为 **「等待重连」**（**不是失败**），并 **自动重连**当前 IP（v1.0.20+）。
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
| **≥~1.7GB HTTP 500** | 上传路径 **nginx → uWSGI → cgi-io** 会先把整包 POST 放在 **`/tmp`（tmpfs）**；默认只有约 **内存一半**。固件升级偶尔用一次 → **`upload-env`** **临时 remount 扩大 `/tmp`（用 RAM）**，`upload-teardown` 恢复；**不在 /data 上为上传专门 bind** |
| 最终镜像文件 | 仍写到 **`/data/firmware.bin`**（大分区）；与 `/tmp` 临时缓冲无关 |
| **保留配置 sysupgrade 后** | 若 overlay 里残留旧版 **cgi-io=/dat** → **`upload-sanity.sh boot`** 恢复 **cgi-io=/tmp** |
| **新固件未点上传** | **v1.0.9+** 按需 `upload-env`（LuCI 上传前自动调用）；未跑则 `/tmp` 仍为默认大小 |
| uwsgi 上传到一半断连 | **`reload-on-as` / `reload-on-rss` 设为 0**，`harakiri=7200`，`limit-as=8192` |
| 上传 HTTP 失败但已落盘 | LuCI 按 `/data/firmware.bin` 大小自动恢复继续校验 |

自检：`/usr/libexec/lede-firmware-upload-check.sh`（`fail=0` 再传 2GB）。**内存建议 ≥4G** 以便把 `/tmp` 扩到 ~2.6G+ 传 2G 级镜像。若见 **cgi-io patched to /dat (legacy)**，执行 **`upload-sanity.sh boot`**。

刷机后 **`47` + `lede-data-mount`** 会跑 **`upload-sanity`**（不常驻 bind）；`lede-cgi-tmp` **禁止 enable**。

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

弹窗内 **「保留当前配置」** 默认勾选 → `sysupgrade` 不带 `-n`，会带回 `/etc/config/` 等；取消则 `-n` 清空配置。

**不是**「新固件首次启动脚本一律不跑」。OpenWrt 在保留配置后仍会执行新镜像的 `/etc/uci-defaults/`。旧版 `99-custom` 会无条件把 LAN 写成 `192.168.9.1`、并可能改 MosDNS/mwan3，看起来像「没保留 IP」。新镜像仅在 **尚未有 LAN 地址** 时写入出厂 `192.168.9.1`。

自定义功能（远程管理、系统报警、MosDNS、mwan3、区域接入中心、局域网安全、Bandix 等）配置都在 `/etc/config/`，勾选保留配置会一并带走。拓扑布局在 `/etc/lede-topo.json`（不在 UCI 目录），已列入 `lib/upgrade/keep.d/lede-custom`。LuCI 脚本、nginx 模板等在镜像 overlay 里，靠新固件本身，不靠备份。
