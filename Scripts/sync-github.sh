#!/usr/bin/env bash
# Create GitHub repo (if needed) and push. Requires: gh auth login (one-time).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GH_BIN="${GH_BIN:-}"
if [[ -z "$GH_BIN" ]]; then
  if command -v gh >/dev/null 2>&1; then
    GH_BIN="$(command -v gh)"
  elif [[ -x "$ROOT/.tools/gh_2.92.0_macOS_arm64/bin/gh" ]]; then
    GH_BIN="$ROOT/.tools/gh_2.92.0_macOS_arm64/bin/gh"
  else
    echo "Installing gh CLI to .tools/ ..."
    mkdir -p "$ROOT/.tools"
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
      ZIP="gh_2.92.0_macOS_arm64.zip"
    else
      ZIP="gh_2.92.0_macOS_amd64.zip"
    fi
    curl -fsSL -o "$ROOT/.tools/gh.zip" "https://github.com/cli/cli/releases/download/v2.92.0/$ZIP"
    unzip -qo "$ROOT/.tools/gh.zip" -d "$ROOT/.tools"
    GH_BIN="$ROOT/.tools/gh_"*/bin/gh
  fi
fi

if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  echo "请先登录 GitHub："
  echo "  $GH_BIN auth login"
  echo "然后重新运行本脚本。"
  exit 1
fi

REPO_NAME="${1:-PDFConverter}"
VISIBILITY="${2:-private}"

if git remote get-url origin >/dev/null 2>&1; then
  echo "已有 remote origin，直接推送 ..."
else
  echo "创建仓库: $REPO_NAME ($VISIBILITY)"
  "$GH_BIN" repo create "$REPO_NAME" \
    --"${VISIBILITY}" \
    --source=. \
    --remote=origin \
    --description "Offline native macOS PDF converter (SwiftUI)" \
    --push
  exit 0
fi

git push -u origin main
echo "完成: $($GH_BIN repo view --json url -q .url)"
