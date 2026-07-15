#!/usr/bin/env bash
# Copies Homebrew-built CLI tools AND their dylib dependencies into Resources/tools
# for fully offline distribution.
#
# v0.4.8 重写：原 bash 版本 edge cases 太多（@rpath/@executable_path 解析、
# bash 3/4 兼容、set -e + cp identical 失败等），改用 Python 实现核心 bundling。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/tools"
mkdir -p "$DEST"

# --- main -------------------------------------------------------------------

echo "Bundling tools into $DEST"
python3 "$(dirname "$0")/bundle_tools.py" --dest "$DEST"

# --- tessdata ---------------------------------------------------------------

if command -v brew &>/dev/null; then
  TESSDATA_SRC="$(brew --prefix tesseract 2>/dev/null)/share/tessdata" || true
  if [[ -d "$TESSDATA_SRC" ]]; then
    mkdir -p "$DEST/tesseract/tessdata"
    cp -R "$TESSDATA_SRC/"* "$DEST/tesseract/tessdata/" 2>/dev/null || true
    echo "✓ tessdata copied"
  fi
fi

# --- ad-hoc codesign -------------------------------------------------------

# 给所有 bundle 进来的工具加 ad-hoc 签名（macOS 14+ 强制要求 dylib 链接签名一致）
echo ""
echo "=== Ad-hoc signing ==="
for d in "$DEST/poppler" "$DEST/qpdf" "$DEST/ghostscript" "$DEST/tesseract"; do
  if [[ -d "$d" ]]; then
    # 先签名 dylib（自底向上顺序很重要）
    while IFS= read -r -d "" lib; do
      codesign --force --sign - "$lib" 2>/dev/null || true
    done < <(find "$d" -type f -name "*.dylib" -print0 | sort -z)

    # 最后签名主二进制
    for bin in "$d"/*; do
      if [[ -x "$bin" ]] && [[ ! "$bin" == *.dylib ]]; then
        codesign --force --sign - "$bin" 2>/dev/null || true
      fi
    done
  fi
done
echo "✓ signing done"

# --- summary ----------------------------------------------------------------

echo ""
echo "=== Bundled tree ==="
find "$DEST" -type f | sort | while read -r f; do
  size=$(du -h "$f" | cut -f1)
  echo "  $size  ${f#$ROOT/}"
done

# --- verification -----------------------------------------------------------

echo ""
echo "=== Verification ==="
FAILED=0
for tool_path in \
    "$DEST/poppler/pdftoppm" \
    "$DEST/poppler/pdftotext" \
    "$DEST/qpdf/qpdf" \
    "$DEST/ghostscript/gs" \
    "$DEST/tesseract/tesseract"; do
  name=$(basename "$tool_path")
  printf "  %-12s ... " "$name"
  if "$tool_path" --version >/dev/null 2>&1 || \
     "$tool_path" -version >/dev/null 2>&1 || \
     "$tool_path" version >/dev/null 2>&1 || \
     "$tool_path" -h >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    otool -L "$tool_path" 2>&1 | grep -E "@rpath|@executable" | head -3 | sed "s/^/    /"
    FAILED=1
  fi
done

if [[ $FAILED -eq 1 ]]; then
  echo ""
  echo "⚠️  验证失败（继续构建，App 启动后会有更详细错误）"
fi
echo ""
echo "✅ Done."
