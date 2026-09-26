# LEDE 升级组件包 — 开发要求

本文说明如何在 **同一套固件 / 同一 overlay 仓库** 上开发、打包、安装 **组件升级包**（LuCI：**系统 → 备份与更新 → 操作 → 组件升级**）。其它设备只要固件里已内置组件升级后端，即可按相同规范制作 `.tar.gz` 包热更新，无需重刷镜像。

---

## 1. 架构约定

| 层级 | 路径 | 作用 |
|------|------|------|
| 运行时 overlay | `files/` | 刷机或 `make` 时进根文件系统，**固件真相源** |
| 组件清单 | `scripts/component-manifests/<name>.list` | 列出要打进某个组件包的 `files/` 相对路径 |
| 包元数据 | `scripts/component-manifests/<name>.meta` | `pack_id`、版本、描述、**输出文件名** |
| 安装后脚本 | `scripts/component-manifests/<name>.post-apply.sh` | 可选；在路由器解压后执行 |
| 打包脚本 | `scripts/build-lede-component-pack.sh` | 生成 `dist/<archive>.tar.gz` |
| 安装器 | `files/usr/libexec/lede-component-apply` | 校验路径、写文件、写状态 |
| LuCI | `files/www/.../flash.js` | 上传 / URL 安装、进度弹窗 |

**原则**

1. **先改 `files/`，再打包** — 组件包内容必须来自 overlay，避免只改 dist 不落库。
2. **固件编译** — `diy-part2.sh` 会把 overlay 拷进 feed 包并做 `assert_grep`，新功能应同步增加自检。
3. **一包一事** — 每个 manifest 对应一个可独立发布的用途（Samba、拓扑 KPI、硬件信息等），避免无关文件混装。
4. **可重复安装** — 同 `pack_id` 可发新版本；覆盖同名路径即可。

---

## 2. 命名规范（文件名，不用时间戳）

在 `<name>.meta` 中写死 **语义化** 压缩包名，便于识别、归档、分发：

```ini
pack_id=lede-component-samba4-network-shares
version=1.0.1
description=Samba 网络共享：UCI 保存并应用、无虚假未保存提示
archive=lede-component-samba4-network-shares-v1.0.1.tar.gz
```

| 字段 | 要求 |
|------|------|
| `pack_id` | 小写、连字符；建议前缀 `lede-component-` + 功能简称 |
| `version` | 语义版本 `major.minor.patch`，**写在 manifest.json 内**，不必塞进文件名日期 |
| `archive` | `dist/` 下最终文件名；建议 `lede-component-<功能>-v<version>.tar.gz` |
| `description` | 一行中文说明，写入 `manifest.json` |

**本仓库已有 manifest 示例**

| manifest 名 | 输出包示例 |
|-------------|------------|
| `lede-component` | `lede-component-upgrader-v1.0.1.tar.gz` |
| `hwinfo` | `lede-component-hwinfo-refresh-v1.0.1.tar.gz` |
| `samba4` | `lede-component-samba4-network-shares-v1.0.1.tar.gz` |
| `topo-hud` | `lede-component-topo-hud-kpi-v1.0.2.tar.gz` |

---

## 3. 允许安装的路径

`lede-component-apply` 仅允许写入以下前缀（见脚本内 `ALLOW_PREFIX`）：

- `usr/libexec/`、`etc/init.d/`、`etc/hotplug.d/`、`etc/uci-defaults/`
- `www/luci-static/`、`usr/share/luci/`、`usr/share/rpcd/`、`usr/share/ucode/`
- `etc/config/`（谨慎：会改 UCI）

**禁止** 通过组件包修改 `etc/passwd`、随意写 `/root` 等；需要新前缀时先改 `lede-component-apply` 并评估安全。

---

## 4. 新建一个组件包的步骤

### 4.1 在 overlay 中实现功能

在 `files/` 下添加或修改脚本、LuCI、ACL 等，并在路由器上自测。

### 4.2 编写清单

`scripts/component-manifests/myfeature.list`（一行一个路径，相对 `files/`）：

```text
# 注释行以 # 开头
www/luci-static/resources/view/foo.js
usr/libexec/my-daemon
```

**依赖后端时**：若包内包含 `usr/libexec/rpcd/*` 或 `usr/share/rpcd/*`，安装后 **不要** 在 `post-apply.sh` 里 `restart rpcd`（会踢掉 LuCI 会话）。安装器默认 **跳过 rpcd 重启**；仅当 manifest 含 `"restart_rpcd": true` 时才重启（一般不需要）。

需要刷新 LuCI 时在 `post-apply.sh` 中：

```sh
rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true
```

### 4.3 编写 meta

`scripts/component-manifests/myfeature.meta`：

```ini
pack_id=lede-component-myfeature
version=1.0.0
description=一句话说明用途
archive=lede-component-myfeature-v1.0.0.tar.gz
```

### 4.4 可选 post-apply

`scripts/component-manifests/myfeature.post-apply.sh`（755）：重启相关 `init.d`、跑一次性脚本等。

### 4.5 打包

在仓库根目录（Mac / Linux 均可）：

```bash
./scripts/build-lede-component-pack.sh myfeature
ls -l dist/
```

一键打齐本仓库全部 manifest 包：

```bash
./scripts/build-all-component-packs.sh
```

### 4.6 安装与验证

1. 路由器：**系统 → 备份与更新 → 操作 → 组件升级**
2. 上传 `dist/*.tar.gz` 或填 URL
3. 等待弹窗「安装成功」，点关闭刷新
4. 相关 LuCI 页 **Ctrl+F5** 强刷
5. 查看 `/tmp/lede-component-apply.log`、`/etc/lede-component-state.json`

---

## 5. manifest.json 格式（自动生成）

打包脚本会生成：

```json
{
  "format": 1,
  "pack_id": "lede-component-xxx",
  "version": "1.0.0",
  "description": "...",
  "files": [
    { "path": "www/...", "mode": "644", "sha256": "..." }
  ]
}
```

可选在 manifest 根增加 `"restart_rpcd": true`（极少使用）。

---

## 6. 与固件编译集成

1. 所有变更落在 `files/` + 必要时 `patches/`。
2. 在 `diy-part2.sh` 的 `assert_overlay` 循环中 **登记新文件**。
3. 增加 `assert_grep '特征字符串' "$_LEDE_FILES/..."` 防止回退。
4. 若改 LuCI feed 内嵌文件，确认 `diy-part2.sh` 里已有对应 `cp files/... feeds/...` 逻辑（如 `index.js`、`flash.js`、`samba4.js`）。
5. 在编译机执行完整或增量 `make` 前，本地可先：

   ```bash
   ./scripts/build-lede-component-pack.sh myfeature
   ```

---

## 7. 开发注意事项

### 7.1 LuCI / RPC

- 组件安装过程用 **`lede-component` status** 轮询（见 `flash.js`），避免安装中途会话失效误判失败。
- 读权限的 RPC 方法应写在 ACL **read**；写操作在 **write**。

### 7.2 Samba / UCI 类页面

- 保存应走 **保存并应用**（`Map.save`），不要后台脚本偷偷 `uci commit` 导致「未保存的配置」。
- 不要用页面加载时的 sync 脚本改写 UCI 与表单争抢。

### 7.3 拓扑 KPI / 报警联动

- 报警 UI 状态应与服务端一致（如 `wanalert_hud_flags` + `sys.alert_hud`），避免前端自己猜阈值。

### 7.4 版本升级

- 发新版：只改 `<name>.meta` 的 `version` 与 `archive`，重新打包。
- 路由器上可同时保留多个不同 `pack_id` 的包；同 id 以最后一次安装为准（覆盖文件）。

### 7.5 其它设备 / 其它固件

- 目标机需已有：**组件升级** 菜单、`lede-component-apply`、`rpcd lede-component`、flash ACL。
- 若缺少，先装 `lede-component-upgrader` 包或刷入含该功能的固件。
- 架构一致（OpenWrt/LEDE + LuCI nginx）即可复用本规范；路径与包名可按项目改，但 **meta 语义化命名** 建议保留。

---

## 8. 故障排查

| 现象 | 排查 |
|------|------|
| 安装报会话过期 | 确认 `lede-component-apply` 未重启 rpcd；升级 `lede-component-upgrader` 包 |
| 安装成功但页面旧 | 强刷浏览器；看 post-apply 是否清缓存 |
| 路径不允许 | 调整清单路径或扩展 `ALLOW_PREFIX`（需评审） |
| 打包 missing | list 中路径必须在 `files/` 下存在 |

---

## 9. 相关文件索引

```
files/usr/libexec/lede-component-apply
files/usr/libexec/rpcd/lede-component
files/www/luci-static/resources/view/system/flash.js
scripts/build-lede-component-pack.sh
scripts/build-all-component-packs.sh
scripts/component-manifests/
dist/                          # 打包输出（可不提交 git）
diy-part2.sh                   # 固件自检与 feed 烘焙
```

维护 overlay → 更新 manifest → 打包 → 安装验证 → 提交源码（含 `files/` 与 manifest，可选提交 `dist/` 作发布附件）。
