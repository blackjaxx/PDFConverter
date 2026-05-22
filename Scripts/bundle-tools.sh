#!/usr/bin/env bash
# Copies Homebrew-built CLI tools into Resources/tools for offline distribution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/tools"
mkdir -p "$DEST"

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
  echo "✓ $name → $DEST/$subdir/$name"
}

echo "Bundling tools into $DEST"
copy_bin pdftoppm poppler
copy_bin pdftotext poppler
copy_bin qpdf qpdf
copy_bin gs ghostscript
copy_bin soffice libreoffice
copy_bin tesseract tesseract

if [[ -d "$(brew --prefix tesseract 2>/dev/null)/share/tessdata" ]]; then
  mkdir -p "$DEST/tesseract/tessdata"
  cp -R "$(brew --prefix tesseract)/share/tessdata/"* "$DEST/tesseract/tessdata/" 2>/dev/null || true
  echo "✓ tessdata copied"
fi

echo "Done. Add Resources/tools to the Xcode app target (folder reference)."
