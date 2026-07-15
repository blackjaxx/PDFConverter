#!/usr/bin/env python3
"""
PDF Converter CLI tools bundling script (v0.4.8).

Resolves @rpath / @executable_path / absolute paths dependencies correctly
using macOS LC_RPATH parsing. Stable across bash versions, no edge case issues.

Usage:
    python3 bundle_tools.py --dest /path/to/Resources/tools
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple


# Tool name → (subdir)
TOOLS = [
    ("pdftoppm", "poppler"),
    ("pdftotext", "poppler"),
    ("qpdf", "qpdf"),
    ("gs", "ghostscript"),
    ("tesseract", "tesseract"),
]

SYSTEM_DYLIB_PREFIXES = (
    "/usr/lib/",
    "/System/Library/",
    "/System/iOSSupport/",
)


def run(cmd):
    return subprocess.check_output(cmd, text=True).strip()


def otool_L(binary):
    """Return list of LC_LOAD_DYLIB names."""
    out = run(["otool", "-L", str(binary)])
    lines = out.split("\n")[1:]
    deps = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        dep = line.split(" ")[0]
        if dep:
            deps.append(dep)
    return deps


def otool_RPATH(binary):
    """Return LC_RPATH entries from `otool -l`.

    Output format:
        Load command N
            cmd LC_RPATH
        cmdsize 32
           path /opt/homebrew/lib (offset 12)
    """
    try:
        out = run(["otool", "-l", str(binary)])
    except subprocess.CalledProcessError:
        return []

    import re
    rpaths = []
    in_rpath = False
    for line in out.split("\n"):
        s = line.strip()
        # 进入 LC_RPATH 段（以 cmd LC_RPATH 起始）
        if re.match(r"cmd\s+LC_RPATH\s*$", s):
            in_rpath = True
            continue
        if in_rpath:
            # path 行：`path /opt/homebrew/lib (offset 12)`
            m = re.match(r"path\s+(\S+)", s)
            if m:
                rpath = m.group(1)
                rpaths.append(rpath)
                in_rpath = False
                continue
            # 下一个 cmd 表示退出
            if s.startswith("cmd ") or s.startswith("Load command"):
                in_rpath = False
    return rpaths


def resolve_dep(dep, binary):
    """Resolve a dylib reference to absolute path."""
    if dep.startswith("/"):
        p = Path(dep)
        return p if p.exists() else None

    if dep.startswith("@executable_path/"):
        rel = dep[len("@executable_path/"):]
        candidate = binary.parent / rel
        return candidate if candidate.exists() else None

    if dep.startswith("@rpath/"):
        rel = dep[len("@rpath/"):]
        for rpath in otool_RPATH(binary):
            if rpath.startswith("@executable_path/"):
                base = binary.parent / rpath[len("@executable_path/"):]
            elif rpath.startswith("/"):
                base = Path(rpath)
            else:
                continue
            candidate = base / rel
            if candidate.exists():
                return candidate.resolve()
        return None

    return None


def is_system_lib(path):
    p = str(path)
    return any(p.startswith(s) for s in SYSTEM_DYLIB_PREFIXES)


COPIED = {}


def copy_dylib(src, subdir_path):
    """Copy dylib to dest/subdir/, set @executable_path/ID, record in cache."""
    src = src.resolve()
    if src in COPIED:
        return COPIED[src]

    dest = subdir_path / src.name
    if not dest.exists():
        shutil.copyfile(str(src), str(dest))
        os.chmod(str(dest), 0o755)
        print(f"  dylib: {src.name} -> {subdir_path.name}/")

    new_id = f"@executable_path/{src.name}"
    subprocess.run(
        ["install_name_tool", "-id", new_id, str(dest)],
        check=False, capture_output=True
    )

    COPIED[src] = dest
    return dest


def relink_binary_to_dylib(binary, original_dep, new_dep_name):
    new_dep = f"@executable_path/{new_dep_name}"
    subprocess.run(
        ["install_name_tool", "-change", original_dep, new_dep, str(binary)],
        check=False, capture_output=True
    )


def process_binary(binary, subdir_path):
    """Recursively resolve and copy all dylib dependencies of binary."""
    processed = set()
    deps = otool_L(binary)
    queue = [(binary, dep) for dep in deps]
    # DEBUG
    print(f"  [debug] {binary.name}: LC_RPATH={otool_RPATH(binary)}", file=sys.stderr)
    print(f"  [debug] {binary.name}: deps={deps}", file=sys.stderr)
    sys.stderr.flush()

    while queue:
        target_bin, dep = queue.pop(0)
        dep_name = os.path.basename(dep)

        src = resolve_dep(dep, target_bin)
        if src is None or is_system_lib(src):
            continue
        src_resolved = src.resolve()
        if src_resolved in processed:
            local_copy = COPIED.get(src_resolved)
            if local_copy is not None:
                relink_binary_to_dylib(target_bin, dep, dep_name)
            continue

        target_subdir = (
            subdir_path if target_bin == binary
            else target_bin.parent
        )
        local_copy = copy_dylib(src_resolved, target_subdir)

        queue.extend((local_copy, d) for d in otool_L(local_copy))
        processed.add(src_resolved)

    # Final pass: relink the top-level binary to all its locally-copied deps
    for dep in otool_L(binary):
        dep_name = os.path.basename(dep)
        src = resolve_dep(dep, binary)
        if src is None or is_system_lib(src):
            continue
        if src.resolve() in COPIED:
            relink_binary_to_dylib(binary, dep, dep_name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dest", required=True)
    args = parser.parse_args()

    dest = Path(args.dest).resolve()
    dest.mkdir(parents=True, exist_ok=True)

    for tool_name, subdir in TOOLS:
        subdir_path = dest / subdir
        subdir_path.mkdir(parents=True, exist_ok=True)

        binary = None
        for d in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]:
            candidate = Path(d) / tool_name
            if candidate.exists() and os.access(candidate, os.X_OK):
                binary = candidate
                break
        if binary is None:
            print(f"warn: skip {tool_name} (not found on PATH)")
            continue

        dest_bin = subdir_path / tool_name
        if dest_bin.exists() or dest_bin.is_symlink():
            dest_bin.unlink()
        shutil.copyfile(str(binary), str(dest_bin))
        os.chmod(str(dest_bin), 0o755)
        print(f"ok: {tool_name} -> {subdir}/")

        COPIED.clear()
        process_binary(dest_bin, subdir_path)

    print("")
    print("Bundling complete.")


if __name__ == "__main__":
    main()
