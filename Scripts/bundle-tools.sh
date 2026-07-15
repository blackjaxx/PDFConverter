#!/usr/bin/env bash
# Copies Homebrew-built CLI tools AND their dylib dependencies into Resources/tools
# for fully offline distribution.
#
# Homebrew binaries are dynamically linked. Without bundling the linked .dylib files,
# the tools will fail with "dyld: Library not loaded" on machines without Homebrew.
# This script uses otool -L + install_name_tool to create a self-contained tool tree.
#
# v0.4.8 修复：之前 head -n 20 截断 + 共享工具被错误塞到第一个 subdir，
#         导致 poppler/qpdf/tesseract 的 dylib 被全部漏打包或装到错位置。
#         重写为按依赖去重，并按 subdir 归类。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/tools"
mkdir -p "$DEST"

# --- helpers ----------------------------------------------------------------

# 解析符号链接 / 不解析符号链接，得到规范的绝对路径
resolve() {
  python3 -c "import os; print(os.path.realpath('$1'))" 2>/dev/null || readlink -f "$1" 2>/dev/null || echo "$1"
}

# 给定一个二进制文件和它的 dylib 路径列表，把每个 dylib 复制到
# Resources/tools/<subdir>/，然后用 install_name_tool -change 修改 binary 的引用，
# 让运行时查找路径指向 @executable_path/<libname>（同目录）。

# 全局去重缓存：<lib_source_path> -> <dest_path_in_tools>
# 避免 bash 3.x（macOS 默认）不支持 declare -A，改用文件持久化
COPIED_LIBS_FILE="$(mktemp -t pdfconverter_bundle.XXXXXX)"
trap "rm -f "$COPIED_LIBS_FILE"" EXIT

copy_lib_to_subdir() {
  local lib_source="$1"
  local subdir="$2"

  # 跳过已复制的（避免重复）
  if grep -Fxq "$lib_source" "$COPIED_LIBS_FILE" 2>/dev/null; then
    local existing
    existing=$(grep -Fx "$lib_source" "$COPIED_LIBS_FILE" | head -1)
    echo "$lib_source 已复制到 $existing" >&2
    return 0
  fi

  local lib_name
  lib_name=$(basename "$lib_source")
  local dest_lib="$DEST/$subdir/$lib_name"

  mkdir -p "$DEST/$subdir"

  # 解析为真实路径（避免 homebrew ../Cellar 符号链接问题）
  local real_lib
  real_lib=$(resolve "$lib_source")

  if [[ ! -f "$real_lib" ]]; then
    echo "⚠️  dylib not found: $lib_source (resolved: $real_lib)" >&2
    return 1
  fi

  cp -f "$real_lib" "$dest_lib" 2>/dev/null || true
  chmod 755 "$dest_lib" 2>/dev/null || true
  # 修改 dylib 的自身 ID，确保其他 dylib 引用它时能找到
  install_name_tool -id "@executable_path/$lib_name" "$dest_lib" 2>/dev/null || true

  echo "$lib_source" >> "$COPIED_LIBS_FILE"
  echo "  dylib copied: $lib_name → $subdir/" >&2

  # 递归处理这个 dylib 的依赖
  fix_dylibs "$dest_lib" "$subdir"
}

# 收集一个 binary 的所有 dylib 依赖（包括 transitive），
# 把它们复制到 subdir，并修改 binary 引用。
fix_dylibs() {
  local target="$1"
  local subdir="$2"

  # 提取所有依赖，处理 @rpath/@executable_path/绝对路径三种情况
  # 使用 otool -L 输出格式: "    libname.dylib (compatibility version X, current version Y)"
  local deps
  # 只看 .dylib 结尾的行（.tbd 等忽略）
  deps=$(otool -L "$target" 2>/dev/null | awk '/\.dylib/ {print $1}' | grep -vE '^/(usr/lib|System/|usr/lib/)' || true)

  if [[ -z "$deps" ]]; then
    return 0
  fi

  for dep in $deps; do
    local lib_path
    lib_path=$(resolve_dep "$dep" "$target")

    # 跳过系统库（/usr/lib/, /System/, 绝对路径且无法解析）
    if [[ -z "$lib_path" ]] || [[ "$lib_path" == /usr/lib/* ]] || [[ "$lib_path" == /System/* ]]; then
      continue
    fi

    # 跳过已经被相同 binary 在同 subdir 引用过的（避免冗余）
    local lib_name
    lib_name=$(basename "$lib_path")

    copy_lib_to_subdir "$lib_path" "$subdir"

    # 修改 binary 引用（无论原来是绝对路径还是 @rpath，都改成 @executable_path/<name>）
    install_name_tool -change "$dep" "@executable_path/$lib_name" "$target" 2>/dev/null || true
  done
}

# 把 otool 输出里的 @rpath/libfoo.dylib 转换为实际路径。
# 策略：
#   1. 如果是绝对路径 → 直接返回
#   2. 如果以 @rpath/ 开头 → 遍历 binary 的所有 LC_RPATH，根据优先级尝试解析
#      （@executable_path/<target_dir> + @rpath/<lib> 形式）
resolve_dep() {
  local dep="$1"
  local binary="$2"

  # 绝对路径（无前缀）
  if [[ "$dep" != @* ]]; then
    if [[ -f "$dep" ]]; then
      realpath "$dep" 2>/dev/null || echo "$dep"
    else
      echo ""
    fi
    return
  fi

  # @executable_path/<lib> → binary 同目录 + lib
  if [[ "$dep" == @executable_path/* ]]; then
    local binary_dir
    binary_dir=$(dirname "$binary")
    local rel_path="${dep#@executable_path/}"
    local candidate="$binary_dir/$rel_path"
    if [[ -f "$candidate" ]]; then
      realpath "$candidate" 2>/dev/null || echo "$candidate"
    else
      echo ""
    fi
    return
  fi

  # @rpath/<lib> → 收集所有 LC_RPATH 后逐个尝试
  if [[ "$dep" == @rpath/* ]]; then
    local rel_path="${dep#@rpath/}"
    local rpaths
    rpaths=$(otool -l "$binary" 2>/dev/null | awk '/LC_RPATH/{flag=1; next} /load command/{flag=0} flag && /path/ {gsub(/^ +path +/, ""); print}' || true)

    for rpath in $rpaths; do
      local candidate

      # @executable_path 在 rpath 里出现
      if [[ "$rpath" == @executable_path/* ]]; then
        local binary_dir
        binary_dir=$(dirname "$binary")
        local r="${rpath#@executable_path/}"
        candidate="$binary_dir/$r/$rel_path"
      elif [[ "$rpath" == /* ]]; then
        candidate="$rpath/$rel_path"
      fi

      if [[ -n "${candidate:-}" ]] && [[ -f "$candidate" ]]; then
        realpath "$candidate" 2>/dev/null || echo "$candidate"
        return
      fi
    done

    echo ""
    return
  fi

  echo ""
}

copy_bin() {
  local name="$1"
  local subdir="$2"
  local path
  path="$(command -v "$name" 2>/dev/null || true)"
  if [[ -z "$path" ]]; then
    echo "⚠️  skip $name (not found on PATH)"
    return
  fi

  local real_path
  real_path=$(resolve "$path")

  mkdir -p "$DEST/$subdir"
  cp -f "$real_path" "$DEST/$subdir/$name"
  chmod +x "$DEST/$subdir/$name"
  echo "✓ $name → $DEST/$subdir/$name"

  # 用 fix_dylibs 处理这个 binary 的依赖
  # 注意：从这个 binary 找到的依赖放到它自己的 subdir 里
  fix_dylibs "$DEST/$subdir/$name" "$subdir"
}

# --- main -------------------------------------------------------------------

echo "Bundling tools into $DEST"

# Poppler: pdftoppm + pdftotext
copy_bin pdftoppm poppler
copy_bin pdftotext poppler

# Qpdf
copy_bin qpdf qpdf

# Ghostscript
copy_bin gs ghostscript

# Tesseract OCR
copy_bin tesseract tesseract

# LibreOffice: skipped – the soffice binary chain is too large to bundle.
echo "⚠️  skipping libreoffice (requires system install of LibreOffice)"

# Tesseract language data
if command -v brew &>/dev/null; then
  TESSDATA_SRC="$(brew --prefix tesseract 2>/dev/null)/share/tessdata" || true
  if [[ -d "$TESSDATA_SRC" ]]; then
    mkdir -p "$DEST/tesseract/tessdata"
    cp -R "$TESSDATA_SRC/"* "$DEST/tesseract/tessdata/" 2>/dev/null || true
    echo "✓ tessdata copied"
  fi
fi

# --- summary ----------------------------------------------------------------

echo ""
echo "=== Bundled tree ==="
find "$DEST" -type f | sort | while read -r f; do
  size=$(du -h "$f" | cut -f1)
  echo "  $size  ${f#$ROOT/}"
done
echo ""
echo "Done."

# 验证：每个工具都能成功执行 --version 不报错
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
  echo -n "  $name ... "
  if "$tool_path" --version >/dev/null 2>&1 || \
     "$tool_path" -version >/dev/null 2>&1 || \
     "$tool_path" version >/dev/null 2>&1 || \
     "$tool_path" -h >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    echo "    诊断: $(otool -L "$tool_path" 2>&1 | grep -E '@rpath|@executable' | head -3)"
    FAILED=1
  fi
done

if [[ $FAILED -eq 1 ]]; then
  echo ""
  echo "❌ 有工具验证失败，请检查上述 dylib 路径"
  exit 1
fi
echo ""
echo "✅ All tools verified OK."
