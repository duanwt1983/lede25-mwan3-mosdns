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
export SSHPASS='编译机密码'
chmod +x scripts/trigger-remote-incremental.sh
./scripts/trigger-remote-incremental.sh root@192.168.6.80
# 编译机上查看：tail -f /openwrt-build/incremental-*.log
```

产物：`$LEDE_WORK/openwrt/bin/targets/x86/64/`。

---

## 2. GitHub Actions（遗留 / 仅手动发版）

- 工作流：`.github/workflows/build-lede.yml`
- **已取消 push 自动触发**；仅 **Actions → Run workflow** 手动跑
- 每次仍是 **全量** 流程（与上面「全新 Ubuntu」相同），适合偶尔从 GitHub 打 Release，**不适合** 日常改组件/ LuCI 迭代

---

## 3. 共同部分

1. `files/` overlay  
2. `patches/*/apply.sh` + `diy-part2.sh`  
3. `package/` 本地 feed  

组件热更新见 [COMPONENT-PACK-DEVELOPMENT.md](COMPONENT-PACK-DEVELOPMENT.md)。

---

## 4. 同步源码到 GitHub

```bash
./scripts/sync-to-github.sh
```

- 只同步 overlay / 文档，**不会** 启动 Actions 编译（工作流无 push 触发）
- 日常开发：**6.80 增量编固件 → 需要时再 push 源码**
