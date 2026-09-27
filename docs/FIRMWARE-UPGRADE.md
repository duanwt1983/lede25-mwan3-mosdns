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

1. **已有 `/data/firmware.bin`**：不自动刷写 →「使用此固件包 / 删除 / 取消」。
2. **上传**：进度**只在弹窗顶部状态栏**；日志不写上传百分比。
3. **上传完成后**：日志立即写「上传完成 → 进入校验…」；校验 / `--test` 长耗时阶段每 **~10 秒**一行阶段日志（非 logread 内核垃圾）。
4. **校验通过后**：必须点 **「确认刷写并重启」** 才 `sysupgrade`。
5. **刷写中**：仅此时轮询 `lede-firmware-progress.sh`（upgrade / dd 命令行 / 写盘字节数）；断连后停止轮询。
6. **刷写成功重启后**：`46-lede-firmware-cleanup` 删除 `/data/firmware.bin`，写入 `/etc/lede-fw-last-flash-success`；再次打开弹窗可见「上次刷写记录」。

---

## 大文件上传依赖（overlay / 组件包）

统一脚本：**`/usr/libexec/lede-firmware-upload-env.sh`**（`45-nginx-firmware-upload`、`lede-cgi-tmp` 均调用它）

| 问题 | 处理 |
|------|------|
| nginx 128M / 413 | 全局与 cgi-upload `client_max_body_size 0` |
| nginx 落盘占满 root | `client_body_temp_path /data/nginx-body` |
| cgi-io 写 `/tmp` tmpfs 满 | 二进制路径改为 `/dat` + bind `/data/cgi-tmp` → `/dat` |
| uwsgi 上传到一半断连 | **`reload-on-as` / `reload-on-rss` 设为 0**，`harakiri=7200`，`limit-as=8192` |
| 上传 HTTP 失败但已落盘 | LuCI 按 `/data/firmware.bin` 大小自动恢复继续校验 |

自检：`/usr/libexec/lede-firmware-upload-check.sh`（`fail=0` 再传 2GB）

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
