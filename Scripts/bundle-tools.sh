#!/usr/bin/env bash
# Copies Homebrew-built CLI tools into Resources/tools for offline distribution.
# Also resolves and bundles dylib dependencies so tools work on any Mac without
# Homebrew installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/tools"
mkdir -p "$DEST"

already_copied=()

fix_dylibs() {
  local binary="$1"
  local dest_dir="$2"

  # Recursively copy all Homebrew dylib dependencies
  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    local dep_name
    dep_name="$(basename "$dep")"

    # 先修改当前二进制的引用（即使 dylib 已被递归调用复制过，引用仍需修改）
    install_name_tool -change "$dep" "@executable_path/$dep_name" "$binary"

    if [[ " ${already_copied[*]:-} " == *" $dep_name "* ]]; then
      continue
    fi
    already_copied+=("$dep_name")

    cp -f "$dep" "$dest_dir/$dep_name"
    chmod u+w "$dest_dir/$dep_name"
    install_name_tool -id "@executable_path/$dep_name" "$dest_dir/$dep_name"

    fix_dylibs "$dest_dir/$dep_name" "$dest_dir"
  done < <(otool -L "$binary" 2>/dev/null | grep -oE '/opt/homebrew/[^ ]+|/usr/local/[^ ]+' | grep -v '\.app/' || true)
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
  chmod +x "$DEST/$subdir/$name"

  already_copied=()
  fix_dylibs "$DEST/$subdir/$name" "$DEST/$subdir"

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