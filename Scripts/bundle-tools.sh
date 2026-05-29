#!/usr/bin/env bash
# Copies Homebrew-built CLI tools AND their dylib dependencies into Resources/tools
# for fully offline distribution.
#
# Homebrew binaries are dynamically linked. Without bundling the linked .dylib files,
# the tools will fail with "dyld: Library not loaded" on machines without Homebrew.
# This script uses otool -L + install_name_tool to create a self-contained tool tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/tools"
mkdir -p "$DEST"

# --- helpers ----------------------------------------------------------------

resolve() {
  python3 -c "import os; print(os.path.realpath('$1'))" 2>/dev/null || readlink -f "$1" 2>/dev/null || echo "$1"
}

fix_dylibs() {
  local target="$1"
  local subdir="$2"

  local deps
  deps=$(otool -L "$target" | grep -oE '/opt/homebrew/[^ ]+|/usr/local/[^ ]+|/usr/local/Cellar/[^ ]+' | head -n 20 || true)

  for lib_path in $deps; do
    local lib_name
    lib_name=$(basename "$lib_path")
    local dest_lib="$DEST/$subdir/$lib_name"

    if [[ ! -f "$dest_lib" ]]; then
      local real_lib
      real_lib=$(resolve "$lib_path")
      if [[ -f "$real_lib" ]]; then
        cp -f "$real_lib" "$dest_lib"
        chmod 755 "$dest_lib"
        install_name_tool -id "@executable_path/$lib_name" "$dest_lib" 2>/dev/null || true
        fix_dylibs "$dest_lib" "$subdir"
      fi
    fi

    install_name_tool -change "$lib_path" "@executable_path/$lib_name" "$target" 2>/dev/null || true
  done
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

  path=$(resolve "$path")
  mkdir -p "$DEST/$subdir"
  cp -f "$path" "$DEST/$subdir/$name"
  chmod +x "$DEST/$subdir/$name"
  echo "✓ $name → $DEST/$subdir/$name"

  fix_dylibs "$DEST/$subdir/$name" "$subdir"
}

copy_bin_with_libs() {
  copy_bin "$1" "$2"
  echo "  → bundled deps: $(find "$DEST/$2" -name '*.dylib' -maxdepth 1 | wc -l | tr -d ' ') dylibs"
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