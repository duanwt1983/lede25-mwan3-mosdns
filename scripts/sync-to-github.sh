#!/usr/bin/env bash
# Sync local overlay repo -> GitHub (duanwt1983/lede25-mwan3-mosdns).
# GitHub Actions: workflow is manual-only (no push trigger); ephemeral runners cannot incremental-build.
set -euo pipefail

REPO="${GITHUB_REPO:-duanwt1983/lede25-mwan3-mosdns}"
BRANCH="${GITHUB_BRANCH:-main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/lede25-sync-$$"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

RSYNC_EX=(
  --archive --delete
  --exclude '.git'
  --exclude '.DS_Store'
  --exclude 'openwrt'
  --exclude 'stress-logs'
  --exclude 'dist'
  --exclude 'tmp-*'
  --exclude 'tmp-topo-pull'
)

echo "Cloning https://github.com/$REPO.git ($BRANCH) ..."
git clone --depth=1 -b "$BRANCH" "https://github.com/$REPO.git" "$WORK"

echo "Rsync local overlay -> clone ..."
rsync "${RSYNC_EX[@]}" "$ROOT/" "$WORK/"

cd "$WORK"
git add -A
if git diff --cached --quiet; then
  echo "Nothing to commit — already in sync with local."
  exit 0
fi

git status --short | head -40
echo "..."

git commit -m "$(cat <<'EOF'
sync: overlay and docs from dev tree (self-hosted build path)

GitHub Actions workflow: manual dispatch only; firmware built on compile host via build-incremental.sh.
EOF
)"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh auth setup-git
fi

echo "Pushing to origin/$BRANCH ..."
if [ -n "${GITHUB_TOKEN:-}" ]; then
  git push "https://${GITHUB_TOKEN}@github.com/${REPO}.git" "HEAD:${BRANCH}"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh auth setup-git
  git push origin "HEAD:${BRANCH}"
else
  echo "No push credentials in this shell. Run in your terminal (after gh auth login):" >&2
  echo "  cd $ROOT && ./scripts/sync-to-github.sh" >&2
  exit 1
fi

echo "Done: https://github.com/$REPO"
