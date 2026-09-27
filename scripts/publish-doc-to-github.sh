#!/usr/bin/env bash
# Push docs/COMPONENT-PACK-DEVELOPMENT.md (and README link) to GitHub overlay repo.
# Requires: git, network, and push access to duanwt1983/lede25-mwan3-mosdns
set -euo pipefail

REPO="${GITHUB_REPO:-duanwt1983/lede25-mwan3-mosdns}"
BRANCH="${GITHUB_BRANCH:-main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC_REL="docs/COMPONENT-PACK-DEVELOPMENT.md"
WORK="${TMPDIR:-/tmp}/lede25-github-publish-$$"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ ! -f "$ROOT/$DOC_REL" ]; then
  echo "Missing $ROOT/$DOC_REL" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required" >&2
  exit 1
fi

upload_via_gh_api() {
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1 || return 1
  local b64 msg
  b64="$(base64 < "$ROOT/$DOC_REL" | tr -d '\n')"
  msg="docs: add LEDE component pack development guide"
  gh api "repos/$REPO/contents/$DOC_REL" \
    -f message="$msg" \
    -f content="$b64" \
    -f branch="$BRANCH" >/dev/null
  echo "Uploaded $DOC_REL via gh api."
  return 0
}

if upload_via_gh_api; then
  echo "Done: https://github.com/$REPO/blob/$BRANCH/$DOC_REL"
  echo "Note: README link not auto-updated in gh-api mode; run full script after gh auth setup-git or edit README on GitHub."
  exit 0
fi

echo "Cloning https://github.com/$REPO.git (branch $BRANCH) ..."
git clone --depth=1 -b "$BRANCH" "https://github.com/$REPO.git" "$WORK"

mkdir -p "$WORK/docs"
cp "$ROOT/$DOC_REL" "$WORK/$DOC_REL"

# README: add 组件升级 row if absent (keep rest of remote README unchanged)
README="$WORK/README.md"
if [ -f "$README" ] && ! grep -q 'COMPONENT-PACK-DEVELOPMENT.md' "$README"; then
  if grep -q '| 文件共享 | samba4' "$README"; then
    python3 - "$README" <<'PY'
import sys
path = sys.argv[1]
row = (
    "| 组件升级 | **系统 → 备份与更新 → 操作 → 组件升级**"
    "（`.tar.gz` 包，无需重刷固件；开发规范见 "
    "[docs/COMPONENT-PACK-DEVELOPMENT.md](docs/COMPONENT-PACK-DEVELOPMENT.md)，"
    "打包 `./scripts/build-lede-component-pack.sh <name>` 或 "
    "`./scripts/build-all-component-packs.sh`） |\n"
)
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
out = []
inserted = False
for line in lines:
    out.append(line)
    if not inserted and line.startswith("| 文件共享 | samba4"):
        out.append(row)
        inserted = True
open(path, "w", encoding="utf-8").writelines(out)
PY
  else
    echo "WARN: README has no samba4 row; add link to $DOC_REL manually." >&2
  fi
fi

cd "$WORK"
git add "$DOC_REL"
if git diff --quiet HEAD -- README.md 2>/dev/null; then
  :
else
  git add README.md
fi

if git diff --cached --quiet; then
  echo "Nothing to commit — GitHub already has the same content."
  exit 0
fi

git commit -m "$(cat <<'EOF'
docs: add LEDE component pack development guide

Documents manifest layout, naming, rpcd/session rules, and diy-part2 integration for LuCI component upgrades.
EOF
)"

echo "Pushing to origin/$BRANCH ..."
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh auth setup-git
fi
git push origin "HEAD:$BRANCH"

echo "Done: https://github.com/$REPO/blob/$BRANCH/$DOC_REL"
