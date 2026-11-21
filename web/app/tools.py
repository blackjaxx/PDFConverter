"""工具定位与子进程执行 —— 桌面版 ToolLocator / ProcessRunner 的 Web 移植。"""
import asyncio
import os
import shutil
from dataclasses import dataclass

from .config import TOOL_TIMEOUT


class ConversionError(Exception):
    """对应桌面版 ConversionError：message 给用户看，details 是完整技术信息。"""

    def __init__(self, message: str, details: str | None = None):
        super().__init__(message)
        self.message = message
        self.details = details


class ToolMissing(ConversionError):
    """对应 ConversionError.missingTool。"""

    def __init__(self, name: str, hint: str | None = None):
        msg = f"未找到工具: {name}"
        if hint:
            msg += f"。{hint}"
        elif name == "soffice":
            msg += "。LibreOffice 转换需要安装：apt install libreoffice / brew install --cask libreoffice"
        else:
            msg += "。Debian/Ubuntu: apt install " + _apt_hint(name) + "；macOS: brew install " + _brew_hint(name)
        super().__init__(msg)


def _apt_hint(name: str) -> str:
    return {"pdftoppm": "poppler-utils", "pdftotext": "poppler-utils", "qpdf": "qpdf",
            "gs": "ghostscript", "tesseract": "tesseract-ocr tesseract-ocr-chi-sim",
            "soffice": "libreoffice"}.get(name, name)


def _brew_hint(name: str) -> str:
    return {"pdftoppm": "poppler", "pdftotext": "poppler", "qpdf": "qpdf", "gs": "ghostscript",
            "tesseract": "tesseract", "soffice": "--cask libreoffice"}.get(name, name)


# 各工具的安装指引（前端「工具箱」与错误提示使用）
INSTALL_INFO: dict[str, dict[str, str]] = {
    "pdftoppm": {"brew": "brew install poppler", "apt": "apt install poppler-utils",
                 "url": "https://poppler.freedesktop.org/", "label": "Poppler"},
    "pdftotext": {"brew": "brew install poppler", "apt": "apt install poppler-utils",
                  "url": "https://poppler.freedesktop.org/", "label": "Poppler"},
    "qpdf": {"brew": "brew install qpdf", "apt": "apt install qpdf",
             "url": "https://qpdf.readthedocs.io/", "label": "qpdf"},
    "gs": {"brew": "brew install ghostscript", "apt": "apt install ghostscript",
           "url": "https://www.ghostscript.com/", "label": "Ghostscript"},
    "tesseract": {"brew": "brew install tesseract tesseract-lang",
                  "apt": "apt install tesseract-ocr tesseract-ocr-chi-sim",
                  "url": "https://github.com/tesseract-ocr/tesseract", "label": "Tesseract OCR"},
    "soffice": {"brew": "brew install --cask libreoffice", "apt": "apt install libreoffice",
                "url": "https://www.libreoffice.org/download/", "label": "LibreOffice"},
    "playwright": {"brew": "pip install playwright && playwright install chromium",
                   "apt": "pip install playwright && playwright install chromium",
                   "url": "https://playwright.dev/python/docs/intro", "label": "Playwright"},
}

# PATH 之外补充常见安装目录：macOS Homebrew + Windows 常见位置
_EXTRA_DIRS = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin",
               "C:\\Program Files\\LibreOffice\\program",
               "C:\\Program Files (x86)\\LibreOffice\\program",
               "C:\\Program Files\\gs\\bin"]

# Windows 上部分工具的可执行文件名不同（如 Ghostscript 控制台版叫 gswin64c）
_WIN_ALIASES = {"gs": ["gswin64c", "gswin32c"]}
_cache: dict[str, str | None] = {}


def find_tool(name: str, refresh: bool = False) -> str | None:
    """查找可执行文件并缓存（对应 ToolLocator.path，去掉了捆绑目录一级）。"""
    if not refresh and name in _cache:
        return _cache[name]
    path = None
    for cand in [name] + _WIN_ALIASES.get(name, []):
        path = shutil.which(cand)
        if not path:
            for d in _EXTRA_DIRS:
                candidate = os.path.join(d, cand)
                if shutil.which(candidate):
                    path = candidate
                    break
        if path:
            break
    _cache[name] = path
    return path


def require_tool(name: str) -> str:
    """引擎内取工具路径；缺失时抛出带安装指引的 ToolMissing。"""
    path = find_tool(name)
    if not path:
        raise ToolMissing(name)
    return path


@dataclass
class ToolResult:
    stdout: str
    stderr: str
    exit_code: int


async def run_tool(argv: list[str], env: dict[str, str] | None = None,
                   timeout: int = TOOL_TIMEOUT) -> ToolResult:
    """执行外部命令（对应 ProcessRunner.run：异步 + 完整捕获 stdout/stderr）。"""
    import os
    merged = None
    if env:
        merged = os.environ.copy()
        merged.update(env)
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, env=merged)
    except FileNotFoundError as e:
        raise ToolMissing(argv[0]) from e
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout)
    except asyncio.TimeoutError:
        proc.kill()
        raise ConversionError(f"命令超时（{timeout}s）", details=" ".join(argv))
    return ToolResult(out.decode("utf-8", errors="replace"),
                      err.decode("utf-8", errors="replace"), proc.returncode or 0)


async def run_checked(argv: list[str], env: dict[str, str] | None = None,
                      timeout: int = TOOL_TIMEOUT) -> str:
    """退出码非 0 时抛 ConversionError（对应 ProcessRunner.runChecked）。"""
    result = await run_tool(argv, env, timeout)
    if result.exit_code != 0:
        raise ConversionError(
            f"命令失败（退出码 {result.exit_code}）",
            details=f"命令: {' '.join(argv)}\n错误输出:\n{result.stderr or '(空)'}",
        )
    return result.stdout
