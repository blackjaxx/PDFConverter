"""转换引擎 —— 桌面版 PDFConverterCore 各 Engine 的 Web 移植。

引擎划分与桌面版一一对应：
- PyMuPDF        ← PDFKitEngine（合并/旋转/水印/图片→PDF）
- Poppler        ← PopplerEngine（PDF→图片 / PDF→文本）
- qpdf           ← QpdfEngine（拆分 / 加密 / 解密）
- Ghostscript    ← GhostscriptEngine（压缩）
- LibreOffice    ← LibreOfficeEngine（Office↔PDF，桌面版的 MS Office/iWork
                   AppleScript 链路在服务端不可用，统一走 LibreOffice）
- Tesseract      ← TesseractEngine（OCR 可搜索 PDF）
- Playwright     ← AppWebKitEngine（HTML→PDF）
- DeepSeek       ← AppLLMEngine（AI 摘要 / 翻译 / Markdown）
"""
import asyncio
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Awaitable, Callable

try:                      # PyMuPDF >= 1.26 推荐新包名
    import pymupdf as fitz
except ImportError:
    import fitz

from .config import DEEPSEEK_API_KEY, DEEPSEEK_BASE_URL, DEEPSEEK_MODEL
from .tools import ConversionError, ToolMissing, require_tool, run_checked, run_tool

ProgressFn = Callable[[float], Awaitable[None]]


@dataclass
class JobContext:
    """对应桌面版 ConversionContext：任务目录、输入文件、参数、进度回调。"""
    job_id: str
    type: str
    inputs: list[Path]
    work_dir: Path
    params: dict
    progress: ProgressFn = field(repr=False, default=None)

    async def set_progress(self, value: float):
        if self.progress:
            await self.progress(value)

    def param(self, key: str, default=None):
        return self.params.get(key, default)

    def page_range(self) -> tuple[int, int | None] | None:
        rng = self.params.get("pageRange")
        if not rng or not rng.get("start"):
            return None
        start = max(1, int(rng["start"]))
        end = int(rng["end"]) if rng.get("end") else None
        return (start, end)

    def output(self, stem: str, suffix: str, ext: str) -> Path:
        """对应 makeOutputURL：输出统一放进 job 目录的 out/ 子目录。"""
        out_dir = self.work_dir / "out"
        out_dir.mkdir(parents=True, exist_ok=True)
        return out_dir / f"{stem}{suffix}.{ext}"


def _stem(path: Path) -> str:
    return path.stem


def _need_input(ctx: JobContext, what: str) -> Path:
    if not ctx.inputs:
        raise ConversionError(f"请选择{what}")
    return ctx.inputs[0]


# ────────────────────────── Poppler 引擎 ──────────────────────────

async def _poppler_pdf_to_images(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "PDF")
    pdftoppm = require_tool("pdftoppm")
    dpi = str(int(ctx.param("dpi", 150)))
    fmt, ext = {"pdfToPNG": ("png", "png"),
                "pdfToJPEG": ("jpeg", "jpg"),
                "pdfToTIFF": ("tiff", "tiff")}[ctx.type]
    stem = _stem(input)
    prefix = ctx.work_dir / "pages" / stem
    prefix.parent.mkdir(parents=True, exist_ok=True)

    args: list[str] = []
    rng = ctx.page_range()
    if rng:
        args += ["-f", str(rng[0])]
        if rng[1]:
            args += ["-l", str(rng[1])]
    if ctx.type == "pdfToJPEG":
        # 桌面版 v0.5.1：jpegQuality 通过 -jpegopt 生效
        quality = max(0, min(100, int(float(ctx.param("jpegQuality", 0.85)) * 100)))
        args += ["-jpegopt", f"quality={quality}"]
    args += [f"-{fmt}", "-r", dpi, str(input), str(prefix)]

    await ctx.set_progress(0.1)
    await run_checked([pdftoppm] + args)
    await ctx.set_progress(0.9)

    files = sorted(prefix.parent.glob(f"{stem}-*.{ext}"), key=lambda p: p.name)
    if not files:
        raise ConversionError("未生成输出文件", details="pdftoppm 退出码为 0 但没有产出图片")
    outs = []
    for f in files:
        dest = ctx.output(stem, "-" + f.stem.split("-")[-1], ext)
        shutil.move(str(f), dest)
        outs.append(dest)
    return outs


async def _poppler_pdf_to_text(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "PDF")
    pdftotext = require_tool("pdftotext")
    out = ctx.output(_stem(input), "_text", "txt")
    args: list[str] = []
    rng = ctx.page_range()
    if rng:
        # 桌面版 v0.5.1：-f 恒定、-l 仅在有结束页时追加
        args += ["-f", str(rng[0])]
        if rng[1]:
            args += ["-l", str(rng[1])]
    args += [str(input), str(out)]
    await ctx.set_progress(0.3)
    await run_checked([pdftotext] + args)
    await ctx.set_progress(0.9)
    if not out.exists():
        raise ConversionError("未生成输出文件", details=str(out))
    return [out]


# ────────────────────────── qpdf 引擎 ──────────────────────────

async def _qpdf_split(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "PDF")
    qpdf = require_tool("qpdf")
    stem = _stem(input)
    out = ctx.output(stem, "_split", "pdf")
    await run_checked([qpdf, "--split-pages", str(input), str(out)])
    # 只收集拆分产物，排除命名基底（桌面版 v0.5.1 同款修正）
    outputs = sorted(out.parent.glob(f"{stem}_split-*.pdf"), key=lambda p: p.name)
    if not outputs:
        raise ConversionError("未生成输出文件", details=str(out))
    return outputs


async def _qpdf_encrypt(ctx: JobContext) -> list[Path]:
    return await _qpdf_crypt(ctx, encrypt=True)


async def _qpdf_decrypt(ctx: JobContext) -> list[Path]:
    return await _qpdf_crypt(ctx, encrypt=False)


async def _qpdf_crypt(ctx: JobContext, encrypt: bool) -> list[Path]:
    input = _need_input(ctx, "PDF")
    qpdf = require_tool("qpdf")
    password = ctx.param("password") or ""
    if not password:
        raise ConversionError("请设置密码")
    suffix = "_encrypted" if encrypt else "_decrypted"
    out = ctx.output(_stem(input), suffix, "pdf")
    if encrypt:
        args = [qpdf, "--encrypt", password, password, "256", "--", str(input), str(out)]
    else:
        args = [qpdf, f"--password={password}", "--decrypt", str(input), str(out)]
    await run_checked(args)
    return [out]


# ────────────────────────── Ghostscript 引擎 ──────────────────────────

async def _gs_compress(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "PDF")
    gs = require_tool("gs")
    level = ctx.param("compressionLevel", "ebook")
    out = ctx.output(_stem(input), "_compressed", "pdf")
    args = ["-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.4", f"-dPDFSETTINGS=/{level}",
            "-dNOPAUSE", "-dQUIET", "-dBATCH", f"-sOutputFile={out}", str(input)]
    await run_checked([gs] + args)
    return [out]


# ────────────────────────── PyMuPDF 引擎（PDFKit 替代） ──────────────────────────

async def _fitz_merge(ctx: JobContext) -> list[Path]:
    if len(ctx.inputs) < 2:
        raise ConversionError("合并至少需要 2 个 PDF")
    merged = fitz.open()
    for path in ctx.inputs:
        with fitz.open(path) as doc:
            merged.insert_pdf(doc)
    out = ctx.output(_stem(ctx.inputs[0]), "_merged", "pdf")
    merged.save(str(out))
    merged.close()
    return [out]


async def _fitz_image_to_pdf(ctx: JobContext) -> list[Path]:
    images = sorted(ctx.inputs, key=lambda p: p.name)
    doc = fitz.open()
    for img in images:
        try:
            pix = fitz.Pixmap(str(img))
            # 像素尺寸按 72dpi 折算成页面点数，与 img2pdf 习惯一致
            page = doc.new_page(width=pix.width, height=pix.height)
            page.insert_image(page.rect, filename=str(img))
            pix = None
        except Exception as e:
            raise ConversionError(f"无法读取图片: {img.name}", details=str(e))
    out = ctx.output(_stem(images[0]), "_merged", "pdf")
    doc.save(str(out))
    doc.close()
    return [out]


async def _fitz_rotate(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "PDF")
    degrees = int(ctx.param("rotationDegrees", 90))
    # 桌面版 v0.5.1：只设置 /Rotate（增量旋转），不交换 mediaBox
    with fitz.open(input) as doc:
        for page in doc:
            page.set_rotation((page.rotation + degrees) % 360)
        out = ctx.output(_stem(input), "_rotated", "pdf")
        doc.save(str(out))
    return [out]


async def _fitz_watermark(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "PDF")
    text = ctx.param("watermarkText") or ""
    if not text.strip():
        raise ConversionError("请输入水印文字")
    with fitz.open(input) as doc:
        # 内置 helv 字体不支持 CJK（会写成问号）：含非 ASCII 时用 china-s（宋体）
        fontname = "helv" if text.isascii() else "china-s"
        for page in doc:
            r = page.rect
            box = fitz.Rect(r.width * 0.25, r.height * 0.45, r.width * 0.75, r.height * 0.45 + 40)
            page.insert_textbox(box, text, fontsize=24, fontname=fontname,
                                color=(0.5, 0.5, 0.5), fill_opacity=0.35,
                                align=fitz.TEXT_ALIGN_CENTER)
        out = ctx.output(_stem(input), "_watermarked", "pdf")
        doc.save(str(out))
    return [out]


# ────────────────────────── LibreOffice 引擎 ──────────────────────────

async def _soffice_convert(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "Office / PDF 文件")
    soffice = require_tool("soffice")
    target = {"wordToPDF": "pdf", "excelToPDF": "pdf", "pptToPDF": "pdf",
              "pdfToWord": "docx", "pdfToExcel": "xlsx"}[ctx.type]
    profile = ctx.work_dir / "lo_profile"
    outbox = ctx.work_dir / "lo_output"
    outbox.mkdir(parents=True, exist_ok=True)
    args = ["--headless", f"-env:UserInstallation=file://{profile}",
            "--convert-to", target, "--outdir", str(outbox), str(input)]
    await run_checked([soffice] + args)
    outputs = sorted(outbox.glob(f"*.{target}"))
    if not outputs:
        raise ConversionError("未生成输出文件",
                              details=f"LibreOffice 转换未产出 .{target}，请确认文件可被 LibreOffice 打开")
    outs = []
    for f in outputs:
        dest = ctx.output(_stem(input), "", target)
        shutil.move(str(f), dest)
        outs.append(dest)
    return outs


# ────────────────────────── Tesseract 引擎 ──────────────────────────

async def _tesseract_ocr(ctx: JobContext) -> list[Path]:
    input = _need_input(ctx, "PDF")
    pdftoppm, tesseract = require_tool("pdftoppm"), require_tool("tesseract")
    langs = str(ctx.param("ocrLanguages", "") or "").strip()
    stem = _stem(input)

    pages_dir = ctx.work_dir / "pages"
    pages_dir.mkdir(parents=True, exist_ok=True)
    await ctx.set_progress(0.1)
    await run_checked([pdftoppm, "-png", "-r", "150", str(input), str(pages_dir / stem)])

    page_images = sorted(pages_dir.glob(f"{stem}-*.png"), key=lambda p: p.name)
    if not page_images:
        raise ConversionError("未生成输出文件", details="pdftoppm 光栅化失败")
    merged = fitz.open()
    total = len(page_images)
    for i, img in enumerate(page_images):
        base = pages_dir / f"{stem}-ocr-{i}"
        args = [tesseract, str(img), str(base)]
        if langs:
            args += ["-l", langs]
        args.append("pdf")
        await run_checked(args)
        pdf_path = base.with_suffix(".pdf")
        with fitz.open(pdf_path) as d:
            merged.insert_pdf(d)
        await ctx.set_progress(0.1 + 0.8 * (i + 1) / total)
    out = ctx.output(stem, "_ocr", "pdf")
    merged.save(str(out))
    merged.close()
    await ctx.set_progress(0.9)
    return [out]


# ────────────────────────── Playwright 引擎（HTML→PDF） ──────────────────────────

async def _playwright_html_to_pdf(ctx: JobContext) -> list[Path]:
    try:
        from playwright.async_api import async_playwright
    except ImportError:
        raise ToolMissing("playwright",
                          "pip install playwright && playwright install chromium")
    input = _need_input(ctx, "HTML 文件")
    out = ctx.output(_stem(input), "", "pdf")
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()
        # 与桌面版一致：以 HTML 所在目录为 baseURL，相对路径资源可解析
        await page.goto(input.resolve().as_uri(), wait_until="load")
        await page.pdf(path=str(out), format="A4")
        await browser.close()
    return [out]


# ────────────────────────── DeepSeek 引擎 ──────────────────────────

_PROMPTS = {
    "pdfAISummary": (
        "你是专业的文档分析助手。根据用户提供的 PDF 正文，用简洁清晰的中文写出结构化摘要（含要点列表）。"
        "不要编造正文中不存在的内容。", "请为以下 PDF 正文生成摘要：", "_summary"),
    "pdfAITranslate": (
        "你是专业翻译。将用户提供的正文准确翻译为{lang}，保持段落结构，专有名词可保留原文并在括号注明。",
        "请将以下正文翻译为{lang}：", "_translated"),
    "pdfAIToMarkdown": (
        "你是文档结构化专家。将正文整理为规范的 Markdown（标题、列表、表格尽量还原），不要添加正文中没有的信息。",
        "请将以下 PDF 正文转为 Markdown：", "_md"),
}


async def _deepseek_ai(ctx: JobContext) -> list[Path]:
    import httpx
    from .catalog import TYPES_BY_KEY
    from .tools import find_tool

    t = TYPES_BY_KEY[ctx.type]
    input = _need_input(ctx, "PDF")
    if input.suffix.lower() != ".pdf":
        raise ConversionError("AI 功能目前仅支持 PDF 文件")

    # 服务端 Key 优先，其次前端按次携带（桌面版 Keychain → 环境变量 / 前端输入）
    api_key = DEEPSEEK_API_KEY or ctx.param("apiKey") or ""
    if not api_key.strip():
        raise ConversionError("请先配置 DeepSeek API Key（服务器环境变量 DEEPSEEK_API_KEY 或页面设置）")

    pdftotext = require_tool("pdftotext")
    if not pdftotext:
        raise ToolMissing("pdftotext")
    tmp_txt = ctx.work_dir / "extract.txt"
    await ctx.set_progress(0.2)
    await run_checked([pdftotext, str(input), str(tmp_txt)])
    raw = tmp_txt.read_text("utf-8", errors="replace").strip()
    if not raw:
        raise ConversionError("未能从 PDF 提取文本，请尝试 OCR 或扫描质量更好的文件")

    max_chars = max(1000, int(ctx.param("aiMaxInputChars", 12000)))
    truncated = len(raw) > max_chars
    chunk = raw[:max_chars]

    system_tpl, user_tpl, suffix = _PROMPTS[ctx.type]
    lang = ctx.param("aiTargetLanguage", "简体中文")
    system = system_tpl.format(lang=lang)
    user = user_tpl.format(lang=lang) + chunk
    if truncated:
        user += "\n\n[注：以下为截断后的正文片段]"
    extra = ctx.param("aiCustomInstruction")
    if extra:
        user += f"\n\n用户附加要求：{extra}"

    await ctx.set_progress(0.4)
    body = {"model": DEEPSEEK_MODEL, "temperature": 0.3, "max_tokens": 4096,
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": user}]}
    root = DEEPSEEK_BASE_URL.rstrip("/")
    async with httpx.AsyncClient(timeout=120) as client:
        resp = await client.post(f"{root}/v1/chat/completions", json=body,
                                 headers={"Authorization": f"Bearer {api_key}"})
    if resp.status_code != 200:
        try:
            msg = resp.json()["error"]["message"]
        except Exception:
            msg = f"HTTP {resp.status_code}"
        raise ConversionError(f"AI 请求失败: {msg}")
    content = (resp.json().get("choices") or [{}])[0].get("message", {}).get("content", "").strip()
    if not content:
        raise ConversionError("AI 请求失败: 模型返回空内容")

    await ctx.set_progress(0.9)
    out = ctx.output(_stem(input), suffix, "md")
    out.write_text(content, "utf-8")
    return [out]


ENGINES: dict[str, Callable[[JobContext], Awaitable[list[Path]]]] = {
    "pdfToPNG": _poppler_pdf_to_images,
    "pdfToJPEG": _poppler_pdf_to_images,
    "pdfToTIFF": _poppler_pdf_to_images,
    "pngToPDF": _fitz_image_to_pdf,
    "jpegToPDF": _fitz_image_to_pdf,
    "pdfToText": _poppler_pdf_to_text,
    "wordToPDF": _soffice_convert,
    "excelToPDF": _soffice_convert,
    "pptToPDF": _soffice_convert,
    "pdfToWord": _soffice_convert,
    "pdfToExcel": _soffice_convert,
    "htmlToPDF": _playwright_html_to_pdf,
    "compressPDF": _gs_compress,
    "mergePDF": _fitz_merge,
    "splitPDF": _qpdf_split,
    "rotatePDF": _fitz_rotate,
    "watermarkPDF": _fitz_watermark,
    "encryptPDF": _qpdf_encrypt,
    "decryptPDF": _qpdf_decrypt,
    "ocrSearchablePDF": _tesseract_ocr,
    "pdfAISummary": _deepseek_ai,
    "pdfAITranslate": _deepseek_ai,
    "pdfAIToMarkdown": _deepseek_ai,
}
