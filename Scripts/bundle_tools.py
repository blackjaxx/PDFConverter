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

    if dep.startswith("@rpath/") or dep.startswith("@loader_path/"):
        prefix_len = len("@rpath/") if dep.startswith("@rpath/") else len("@loader_path/")
        rel = dep[prefix_len:]

        # 1) 用 binary 的 LC_RPATH 表解析（可能含 @loader_path/@executable_path）
        for rpath in otool_RPATH(binary):
            if rpath.startswith("@executable_path/") or rpath.startswith("@loader_path/"):
                rp_prefix = len("@executable_path/") if rpath.startswith("@executable_path/") else len("@loader_path/")
                base = binary.parent / rpath[rp_prefix:]
            elif rpath.startswith("/"):
                base = Path(rpath)
            else:
                continue
            candidate = base / rel
            if candidate.exists():
                return candidate.resolve()

        # 2) Homebrew 兜底：常规搜索路径
        rel_name = rel.split("/")[-1] if "/" in rel else rel
        for sys_root in [
            "/opt/homebrew/lib",
            "/usr/local/lib",
            "/usr/lib",
            "/Library/Apple/usr/lib",
        ]:
            # 也试试符号链接可能存在的结构
            candidate = Path(sys_root) / rel
            if candidate.exists():
                return candidate.resolve()
            # libpoppler.161.dylib 这种带版本号的，搜索上级目录
            for subdir in [".", ".."]:
                candidate = Path(sys_root) / subdir / rel
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

    full_name = src.name  # e.g. libpoppler.161.0.0.dylib
    # 提取短名：去掉末尾的额外版本号段
    # 例：libpoppler.161.0.0.dylib -> libpoppler.161.dylib
    parts = full_name.replace(".dylib", "").split(".")
    if len(parts) >= 3:
        short_name = ".".join(parts[:2]) + ".dylib"
    else:
        short_name = full_name

    dest_full = subdir_path / full_name
    dest_short = subdir_path / short_name

    if not dest_full.exists():
        shutil.copyfile(str(src), str(dest_full))
        os.chmod(str(dest_full), 0o755)
        print(f"  dylib: {full_name} -> {subdir_path.name}/")

    # macOS libsymlink: 短名 -> 全名
    if full_name != short_name:
        if dest_short.exists() or dest_short.is_symlink():
            dest_short.unlink()
        os.symlink(full_name, str(dest_short))
        print(f"     sym: {short_name} -> {full_name}")

    # Dylib 自身 ID 用短名（binaries 也用短名引用）
    new_id = f"@executable_path/{short_name}"
    subprocess.run(
        ["install_name_tool", "-id", new_id, str(dest_full)],
        check=False, capture_output=True
    )

    COPIED[src] = dest_full
    if full_name != short_name:
        COPIED[short_name] = dest_full
    return dest_full


def relink_binary_to_dylib(binary, original_dep, new_dep_name):
    """把 binary 的 original_dep 引用改为 @executable_path/<dylib 短名>.

    new_dep_name 是 dylib 的 basename (libfoo.A.B.C.dylib 或 libfoo.A.dylib).
    """
    parts = new_dep_name.replace(".dylib", "").split(".")
    if len(parts) >= 3:
        short_name = ".".join(parts[:2]) + ".dylib"
    else:
        short_name = new_dep_name

    new_dep = f"@executable_path/{short_name}"
    subprocess.run(
        ["install_name_tool", "-change", original_dep, new_dep, str(binary)],
        check=False, capture_output=True
    )


def process_binary(binary, subdir_path):
    """Recursively resolve and copy all dylib dependencies of binary."""
    processed = set()
    queue = [(binary, dep) for dep in otool_L(binary)]

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
