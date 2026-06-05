#!/usr/bin/env bash
# Copies Homebrew-built CLI tools into Resources/tools for offline distribution.
# Also resolves and bundles dylib dependencies so tools work on any Mac without
# Homebrew installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/tools"
mkdir -p "$DEST"

already_copied=()

resolve_rpath() {
  local binary="$1"
  local rpath_ref="$2"
  local dylib_name="${rpath_ref#@rpath/}"
  local binary_dir
  binary_dir="$(dirname "$binary")"

  # 1) 从 LC_RPATH 中查找
  while IFS= read -r rpath; do
    [[ -z "$rpath" ]] && continue
    rpath="${rpath//@loader_path/$binary_dir}"
    rpath="${rpath//@executable_path/$binary_dir}"
    local candidate="$rpath/$dylib_name"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done < <(otool -l "$binary" 2>/dev/null | grep -A2 'LC_RPATH' | grep 'path' | sed 's/.*path //' | sed 's/ (.*//')

  # 2) Fallback: 搜索 Homebrew 常见路径
  local brew_prefix
  brew_prefix="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"
  for fallback in "$brew_prefix/lib" "$brew_prefix/opt"/*/lib /usr/local/lib "$binary_dir"; do
    [[ -f "$fallback/$dylib_name" ]] || continue
    echo "$fallback/$dylib_name"
    return 0
  done

  # 3) Last resort: 在整个 Homebrew prefix 中搜索
  local found
  found="$(find "$brew_prefix" -name "$dylib_name" -type f 2>/dev/null | head -1)"
  if [[ -n "$found" ]]; then
    echo "$found"
    return 0
  fi

  return 1
}

fix_dylibs() {
  local binary="$1"
  local dest_dir="$2"
  local original_binary="${3:-$binary}"

  # Recursively copy all Homebrew dylib dependencies (absolute + @rpath)
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue

    local original_dep="$dep"
    local dep_name

    if [[ "$dep" == @rpath/* ]]; then
      dep="$(resolve_rpath "$original_binary" "$dep")"
      if [[ -z "$dep" ]]; then
        continue
      fi
    fi

    dep_name="$(basename "$dep")"

    install_name_tool -change "$original_dep" "@executable_path/$dep_name" "$binary"

    if [[ " ${already_copied[*]:-} " == *" $dep_name "* ]]; then
      continue
    fi
    already_copied+=("$dep_name")

    cp -f "$dep" "$dest_dir/$dep_name"
    chmod u+w "$dest_dir/$dep_name"
    install_name_tool -id "@executable_path/$dep_name" "$dest_dir/$dep_name"

    fix_dylibs "$dest_dir/$dep_name" "$dest_dir" "$dep"
  done < <(otool -L "$binary" 2>/dev/null | grep -oE '/opt/homebrew/[^ ]+|/usr/local/[^ ]+|@rpath/[^ ]+' | grep -v '\.app/' || true)
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
  mkdir -p "$DEST/$subdir"
  cp -f "$path" "$DEST/$subdir/$name"
  chmod u+w "$DEST/$subdir/$name"

  already_copied=()
  fix_dylibs "$DEST/$subdir/$name" "$DEST/$subdir" "$path"

  # 安全网: 将工具目录加入 rpath，确保即使某些 @rpath 引用未被解析
  # dyld 仍能在工具所在目录找到 dylib
  install_name_tool -add_rpath "@executable_path" "$DEST/$subdir/$name" 2>/dev/null || true

  echo "✓ $name → $DEST/$subdir/$name"
}

echo "Bundling tools into $DEST"
copy_bin pdftoppm    poppler
copy_bin pdftotext   poppler
copy_bin qpdf        qpdf
copy_bin gs          ghostscript
copy_bin tesseract   tesseract

# LibreOffice is too large to bundle (hundreds of MB of dylibs).
# Users must install it separately from https://www.libreoffice.org/download/
if command -v soffice &>/dev/null; then
  echo "⚠️  skip soffice — LibreOffice is too large to bundle. Install it separately."
fi

if [[ -d "$(brew --prefix tesseract 2>/dev/null)/share/tessdata" ]]; then
  mkdir -p "$DEST/tesseract/tessdata"
  cp -R "$(brew --prefix tesseract)/share/tessdata/"* "$DEST/tesseract/tessdata/" 2>/dev/null || true
  echo "✓ tessdata copied"
fi

echo "Done. Add Resources/tools to the Xcode app target (folder reference)."