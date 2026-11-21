"""转换类型目录 —— 桌面版 ConversionType / ConversionCategory 的 Web 移植。

类型键、分类、显示名与桌面版一一对应；参数描述符供前端动态渲染
（对应桌面版 ConversionOptionsView 的逐类型参数面板）。
"""
from dataclasses import dataclass, field
from typing import Any

# 各分类显示名（对应 ConversionCategory.displayName）
CATEGORIES: list[tuple[str, str]] = [
    ("pdfToImage", "PDF → 图片"),
    ("imageToPDF", "图片 → PDF"),
    ("pdfToText", "PDF → 文本"),
    ("officeToPDF", "Office → PDF"),
    ("pdfToOffice", "PDF → Office"),
    ("htmlToPDF", "网页"),
    ("compress", "优化"),
    ("merge", "页面"),
    ("split", "页面"),
    ("rotate", "编辑"),
    ("watermark", "编辑"),
    ("encrypt", "安全"),
    ("decrypt", "安全"),
    ("ocr", "OCR"),
    ("ai", "AI (DeepSeek)"),
]

# 各分类的参数描述符（前端据此渲染参数面板）
PARAM_DEFS: dict[str, list[dict[str, Any]]] = {
    "pdfToImage": [
        {"key": "dpi", "label": "DPI", "type": "stepper", "min": 72, "max": 600, "step": 25, "default": 150},
        {"key": "pageRange", "label": "页码范围", "type": "range"},
        {"key": "jpegQuality", "label": "JPEG 质量", "type": "stepper", "min": 10, "max": 100,
         "step": 5, "default": 85, "onlyFor": "pdfToJPEG", "unit": "%"},
    ],
    "imageToPDF": [],
    "pdfToText": [{"key": "pageRange", "label": "页码范围", "type": "range"}],
    "officeToPDF": [],
    "pdfToOffice": [],
    "htmlToPDF": [],
    "compress": [
        {"key": "compressionLevel", "label": "压缩档位", "type": "select",
         "options": [["screen", "屏幕（最小）"], ["ebook", "电子书（推荐）"], ["printer", "打印"],
                     ["prepress", "印前"], ["default", "默认（接近原质量）"]],
         "default": "ebook"},
    ],
    "merge": [],
    "split": [],
    "rotate": [
        {"key": "rotationDegrees", "label": "旋转角度", "type": "select",
         "options": [[90, "90°"], [180, "180°"], [270, "270°"]], "default": 90},
    ],
    "watermark": [
        {"key": "watermarkText", "label": "水印文字", "type": "text", "placeholder": "请输入水印文字"},
        {"key": "watermarkFontSize", "label": "字号", "type": "stepper", "min": 12, "max": 72,
         "step": 4, "default": 24},
    ],
    "encrypt": [{"key": "password", "label": "密码", "type": "password"}],
    "decrypt": [{"key": "password", "label": "密码", "type": "password"}],
    "ocr": [{"key": "ocrLanguages", "label": "OCR 语言", "type": "chips",
             "default": "chi_sim+eng", "placeholder": "chi_sim+eng",
             "options": [["chi_sim+eng", "简体+英文"], ["eng", "纯英文"],
                         ["chi_tra+eng", "繁体+英文"], ["jpn+eng", "日文+英文"]]}],
    "ai": [
        {"key": "aiTargetLanguage", "label": "翻译语言", "type": "select",
         "options": [["简体中文", "简体中文"], ["English", "English"], ["日本語", "日本語"]],
         "default": "简体中文", "onlyFor": "pdfAITranslate"},
        {"key": "aiMaxInputChars", "label": "字符上限", "type": "stepper", "min": 2000, "max": 50000,
         "step": 1000, "default": 12000},
        {"key": "aiCustomInstruction", "label": "附加指令", "type": "text", "placeholder": "例如：请用表格呈现"},
    ],
}


@dataclass
class ConversionType:
    key: str
    category: str
    display: str
    engine: str                 # 引擎标识（对应桌面版 EngineKind）
    engine_display: str
    multiple: bool = False      # 是否允许多选文件
    tool: str | None = None     # 依赖的 CLI 工具（None = 纯 Python / 特殊判断）
    tool2: str | None = None    # 部分类型依赖两个工具（如 OCR）
    needs_key: bool = False     # 是否需要 DeepSeek Key
    accept: list[str] = field(default_factory=list)  # 允许的文件扩展名（空 = 不限）

    def params(self) -> list[dict[str, Any]]:
        return PARAM_DEFS.get(self.category, [])


TYPES: list[ConversionType] = [
    ConversionType("pdfToPNG", "pdfToImage", "PDF → PNG", "poppler", "Poppler", tool="pdftoppm", accept=[".pdf"]),
    ConversionType("pdfToJPEG", "pdfToImage", "PDF → JPEG", "poppler", "Poppler", tool="pdftoppm", accept=[".pdf"]),
    ConversionType("pdfToTIFF", "pdfToImage", "PDF → TIFF", "poppler", "Poppler", tool="pdftoppm", accept=[".pdf"]),
    ConversionType("pngToPDF", "imageToPDF", "PNG → PDF", "pymupdf", "PyMuPDF", multiple=True, accept=[".png"]),
    ConversionType("jpegToPDF", "imageToPDF", "JPEG → PDF", "pymupdf", "PyMuPDF", multiple=True, accept=[".jpg", ".jpeg"]),
    ConversionType("pdfToText", "pdfToText", "PDF → 文本", "poppler", "Poppler", tool="pdftotext", accept=[".pdf"]),
    ConversionType("wordToPDF", "officeToPDF", "Word → PDF", "libreOffice", "LibreOffice", tool="soffice", accept=[".docx", ".doc", ".rtf", ".odt", ".txt"]),
    ConversionType("excelToPDF", "officeToPDF", "Excel → PDF", "libreOffice", "LibreOffice", tool="soffice", accept=[".xlsx", ".xls", ".csv", ".ods"]),
    ConversionType("pptToPDF", "officeToPDF", "PPT → PDF", "libreOffice", "LibreOffice", tool="soffice", accept=[".pptx", ".ppt", ".odp"]),
    ConversionType("pdfToWord", "pdfToOffice", "PDF → Word", "libreOffice", "LibreOffice", tool="soffice", accept=[".pdf"]),
    ConversionType("pdfToExcel", "pdfToOffice", "PDF → Excel", "libreOffice", "LibreOffice", tool="soffice", accept=[".pdf"]),
    ConversionType("htmlToPDF", "htmlToPDF", "HTML → PDF", "playwright", "Playwright", accept=[".html", ".htm"]),
    ConversionType("compressPDF", "compress", "压缩 PDF", "ghostscript", "Ghostscript", tool="gs", accept=[".pdf"]),
    ConversionType("mergePDF", "merge", "合并 PDF", "pymupdf", "PyMuPDF", multiple=True, accept=[".pdf"]),
    ConversionType("splitPDF", "split", "拆分 PDF", "qpdf", "qpdf", tool="qpdf", accept=[".pdf"]),
    ConversionType("rotatePDF", "rotate", "旋转页面", "pymupdf", "PyMuPDF", accept=[".pdf"]),
    ConversionType("watermarkPDF", "watermark", "添加水印", "pymupdf", "PyMuPDF", accept=[".pdf"]),
    ConversionType("encryptPDF", "encrypt", "加密 PDF", "qpdf", "qpdf", tool="qpdf", accept=[".pdf"]),
    ConversionType("decryptPDF", "decrypt", "解密 PDF", "qpdf", "qpdf", tool="qpdf", accept=[".pdf"]),
    ConversionType("ocrSearchablePDF", "ocr", "OCR 可搜索 PDF", "tesseract", "Tesseract",
                   tool="tesseract", tool2="pdftoppm", accept=[".pdf"]),
    ConversionType("pdfAISummary", "ai", "AI 摘要 (DeepSeek)", "deepSeek", "DeepSeek", needs_key=True, accept=[".pdf"]),
    ConversionType("pdfAITranslate", "ai", "AI 翻译 (DeepSeek)", "deepSeek", "DeepSeek", needs_key=True, accept=[".pdf"]),
    ConversionType("pdfAIToMarkdown", "ai", "AI → Markdown (DeepSeek)", "deepSeek", "DeepSeek", needs_key=True, accept=[".pdf"]),
]

TYPES_BY_KEY = {t.key: t for t in TYPES}


def type_brief(t: ConversionType, tool_status: dict[str, bool], has_server_key: bool) -> dict[str, Any]:
    """序列化为前端所需的类型描述（含可用性判断，对应 isBackendAvailable）。"""
    if t.tool and not tool_status.get(t.tool):
        available, reason = False, f"缺少工具 {t.tool}"
    elif t.tool2 and not tool_status.get(t.tool2):
        available, reason = False, f"缺少工具 {t.tool2}"
    elif t.key == "htmlToPDF" and not tool_status.get("playwright"):
        available, reason = False, "未安装 playwright（pip install playwright && playwright install chromium）"
    elif t.needs_key and not (has_server_key or True):
        # 前端可自带 Key，因此 AI 类型始终可选，缺少服务端 Key 时提示
        available, reason = True, ""
    else:
        available, reason = True, ""
    return {
        "key": t.key,
        "category": t.category,
        "display": t.display,
        "engine": t.engine,
        "engineDisplay": t.engine_display,
        "multiple": t.multiple,
        "available": available,
        "unavailableReason": reason,
        "needsKey": t.needs_key,
        "tool": t.tool,
        "tool2": t.tool2,
        "accept": t.accept,
        "params": t.params(),
    }
