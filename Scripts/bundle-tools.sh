#!/usr/bin/env bash
# Copies Homebrew-built CLI tools into Resources/tools for offline distribution.
# Also resolves and bundles dylib dependencies so tools work on any Mac without
# Homebrew installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/tools"
mkdir -p "$DEST"

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"

already_copied=()

resolve_rpath() {
  local binary="$1"
  local rpath_ref="$2"
  local dylib_name="${rpath_ref#@rpath/}"
  local binary_dir
  binary_dir="$(dirname "$binary")"

  # 1) Search LC_RPATH entries
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

  # 2) Fallback: scan Homebrew lib and opt/*/lib
  for fallback in "$BREW_PREFIX/lib" "$BREW_PREFIX/opt"/*/lib /usr/local/lib "$binary_dir"; do
    [[ -f "$fallback/$dylib_name" ]] || continue
    echo "$fallback/$dylib_name"
    return 0
  done

  # 3) Last resort: find across the entire Homebrew prefix
  local found
  found="$(find "$BREW_PREFIX" -name "$dylib_name" -type f 2>/dev/null | head -1)"
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

  while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue

    local original_dep="$dep"
    local dep_name

    if [[ "$dep" == @rpath/* ]]; then
      dep="$(resolve_rpath "$original_binary" "$dep")"
      if [[ -z "$dep" ]]; then
        echo "   ⚠️  unresolved @rpath: $original_dep (from $binary)"
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
    # Also add @executable_path to the dylib's own rpath so it can find
    # other dylibs in the same directory
    install_name_tool -add_rpath "@executable_path" "$dest_dir/$dep_name" 2>/dev/null || true

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

  install_name_tool -add_rpath "@executable_path" "$DEST/$subdir/$name" 2>/dev/null || true

  echo "✓ $name → $DEST/$subdir/$name"
}

# ─────────────────────────────────────────────────────────────────────
# Post-processing: scan all bundled binaries for any remaining
# @rpath or Homebrew-absolute references and try to fix them.
# ─────────────────────────────────────────────────────────────────────
fix_remaining() {
  echo ""
  echo "=== Post-processing: checking for remaining dylib references ==="

  # Reset global dedup array so fix_dylibs won't incorrectly skip dylibs
  # that were already copied by earlier copy_bin calls but may be needed
  # in a different subdirectory.
  already_copied=()

  local max_iterations=5
  local iteration=0
  local changed=1

  while [[ $changed -eq 1 && $iteration -lt $max_iterations ]]; do
    changed=0
    iteration=$((iteration + 1))
    echo "--- Pass $iteration ---"

    while IFS= read -r -d '' binary; do
      while IFS= read -r dep; do
        [[ -z "$dep" ]] && continue
        local original_dep="$dep"
        local dep_name

        if [[ "$dep" == @rpath/* ]]; then
          # Resolve @rpath using the binary's OWN LC_RPATH (not the original)
          dep="$(resolve_rpath "$binary" "$dep")"
          if [[ -z "$dep" ]]; then
            # Try to find by name in the dest tree or Homebrew
            dep_name="${original_dep#@rpath/}"
            local found_in_dest
            found_in_dest="$(find "$DEST" -name "$dep_name" -type f 2>/dev/null | head -1)"
            if [[ -n "$found_in_dest" ]]; then
              local bin_dir
              bin_dir="$(dirname "$binary")"
              if [[ "$found_in_dest" != "$bin_dir/$dep_name" ]]; then
                # Dylib found in a different directory — copy to current dir
                echo "   fix leftover @rpath: $original_dep → copy from $found_in_dest"
                cp -f "$found_in_dest" "$bin_dir/$dep_name"
                chmod u+w "$bin_dir/$dep_name"
              fi
              install_name_tool -change "$original_dep" "@executable_path/$dep_name" "$binary"
              changed=1
            else
              echo "   ⚠️  still unresolved @rpath: $original_dep in $(basename "$binary")"
            fi
            continue
          fi
        fi

        dep_name="$(basename "$dep")"
        local dest_dir
        dest_dir="$(dirname "$binary")"

        if [[ -f "$dest_dir/$dep_name" ]]; then
          # Already in the same directory, just fix the reference
          if [[ "$original_dep" != "@executable_path/$dep_name" ]]; then
            echo "   fix leftover ref: $original_dep in $(basename "$binary")"
            install_name_tool -change "$original_dep" "@executable_path/$dep_name" "$binary"
            changed=1
          fi
        else
          # Copy the missing dylib
          echo "   fix missing dylib: $dep_name → $(basename "$(dirname "$binary")")/"
          cp -f "$dep" "$dest_dir/$dep_name"
          chmod u+w "$dest_dir/$dep_name"
          install_name_tool -id "@executable_path/$dep_name" "$dest_dir/$dep_name"
          install_name_tool -add_rpath "@executable_path" "$dest_dir/$dep_name" 2>/dev/null || true
          install_name_tool -change "$original_dep" "@executable_path/$dep_name" "$binary"
          changed=1

          # Recurse into the newly copied dylib
          already_copied=()
          fix_dylibs "$dest_dir/$dep_name" "$dest_dir" "$dep"
        fi
      done < <(otool -L "$binary" 2>/dev/null | grep -oE '/opt/homebrew/[^ ]+|/usr/local/[^ ]+|@rpath/[^ ]+' | grep -v '\.app/' || true)
    done < <(find "$DEST" -type f \( -perm /0111 -o -name '*.dylib' \) -print0 2>/dev/null)
  done

  echo ""
  echo "=== Post-processing complete ==="
}

# ─────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────
echo "Bundling tools into $DEST"
echo "Homebrew prefix: $BREW_PREFIX"
echo ""

copy_bin pdftoppm    poppler
copy_bin pdftotext   poppler
copy_bin qpdf        qpdf
copy_bin gs          ghostscript
copy_bin tesseract   tesseract

# LibreOffice is too large to bundle (hundreds of MB of dylibs).
if command -v soffice &>/dev/null; then
  echo "⚠️  skip soffice — LibreOffice is too large to bundle. Install it separately."
fi

if [[ -d "$BREW_PREFIX/share/tessdata" ]]; then
  mkdir -p "$DEST/tesseract/tessdata"
  cp -R "$BREW_PREFIX/share/tessdata/"* "$DEST/tesseract/tessdata/" 2>/dev/null || true
  echo "✓ tessdata copied"
elif [[ -d "$(brew --prefix tesseract 2>/dev/null)/share/tessdata" ]]; then
  mkdir -p "$DEST/tesseract/tessdata"
  cp -R "$(brew --prefix tesseract)/share/tessdata/"* "$DEST/tesseract/tessdata/" 2>/dev/null || true
  echo "✓ tessdata copied (from tesseract opt)"
fi

# Run post-processing fix pass
fix_remaining

# Diagnostic output
echo ""
echo "=== Final bundled binaries with otool -L ==="
find "$DEST" -type f \( -perm /0111 -o -name '*.dylib' \) -print0 2>/dev/null | while IFS= read -r -d '' f; do
  echo "--- $(basename "$f") [$(dirname "$f" | sed "s|$DEST/||")] ---"
  otool -L "$f" 2>/dev/null | grep -iE '(homebrew|@rpath|@executable_path|not found)' || echo "  (all deps resolved)"
done || true

echo ""
echo "Done. Add Resources/tools to the Xcode app target (folder reference)."