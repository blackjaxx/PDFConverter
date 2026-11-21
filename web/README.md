# PDF Converter Web

macOS 桌面版 [PDFConverter](../README.md) 的 **B/S 架构移植版**：浏览器上传 → 服务器转换 → 下载结果。
转换引擎与桌面版一一对应（Poppler / qpdf / Ghostscript / Tesseract / LibreOffice / DeepSeek），
桌面版 PDFKit 引擎的功能（合并/旋转/水印/图片→PDF）由纯 Python 的 PyMuPDF 实现。

## 快速开始

### 方式一：Docker（推荐，一键起、工具全内置）

```bash
cd web
docker compose up -d --build
# 浏览器打开 http://localhost:8000
```

如需 AI 功能：`DEEPSEEK_API_KEY=sk-xxx docker compose up -d --build`

### 方式二：本地运行（开发）

```bash
cd web
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 转换工具（按需安装，缺哪个功能就少哪个，页面会显示红点）
brew install poppler qpdf ghostscript tesseract          # macOS
# apt install poppler-utils qpdf ghostscript tesseract-ocr libreoffice   # Debian/Ubuntu
brew install --cask libreoffice

uvicorn app.main:app --port 8000
# 或使用开发启动器（SIGUSR1 可转储协程任务栈，便于排查卡住的任务）
python run.py --port 8000
```

## 功能对照（与桌面版）

| 功能 | 引擎 | 说明 |
|---|---|---|
| PDF → PNG / JPEG / TIFF | Poppler | 支持 DPI / 页码范围 / JPEG 质量 |
| PNG / JPEG → PDF | PyMuPDF | 多图合一，按文件名排序 |
| PDF → 文本 | Poppler | 支持页码范围 |
| Word / Excel / PPT → PDF | LibreOffice headless | 独立 profile，防并发锁冲突 |
| PDF → Word / Excel | LibreOffice headless | |
| 压缩 PDF | Ghostscript | screen / ebook / printer / prepress |
| 合并 / 旋转 / 水印 | PyMuPDF | 旋转为无损 /Rotate（对齐桌面版 v0.5.1 修复） |
| 拆分 / 加密 / 解密 | qpdf | AES-256 |
| OCR 可搜索 PDF | Poppler + Tesseract | 先光栅化再逐页 OCR，支持 chi_sim+eng |
| HTML → PDF | Playwright (Chromium) | 需 `pip install playwright && playwright install chromium`（Docker 镜像未内置） |
| AI 摘要 / 翻译 / Markdown | DeepSeek API | Key 来自环境变量或浏览器 localStorage |

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PDFCONV_DATA_DIR` | `./data` | 任务与输出文件的存储目录 |
| `PDFCONV_UPLOAD_LIMIT_MB` | `100` | 单次上传总大小上限 |
| `PDFCONV_MAX_CONCURRENT` | `2` | 同时执行的转换任务数 |
| `PDFCONV_ACCESS_TOKEN` | 空 | 设置后所有 API 需携带 `X-Access-Token` 头（公网部署建议开启） |
| `DEEPSEEK_API_KEY` | 空 | 服务端 AI Key（设置后前端无需再填） |
| `DEEPSEEK_BASE_URL` / `DEEPSEEK_MODEL` | 官方 / deepseek-chat | AI 接口配置 |

## API 一览

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/types` | 转换类型目录（含可用性与参数描述符） |
| GET | `/api/tools` | CLI 工具可用性报告 |
| POST | `/api/jobs` | 提交任务（multipart：`type` + `params`(JSON) + `files[]`） |
| GET | `/api/jobs` | 任务快照（按创建时间倒序） |
| GET | `/api/jobs/{id}` | 单个任务 |
| GET | `/api/events` | SSE 实时任务流（15s 心跳） |
| GET | `/api/jobs/{id}/files/{name}` | 下载输出文件 |
| DELETE | `/api/jobs/{id}` | 移除任务（同时删除其文件） |
| POST | `/api/jobs/{id}/retry` | 以原参数重试 |
| POST | `/api/jobs/clear-completed` / `clear-all` | 批量清理 |

## 安全提示

- 公网部署务必设置 `PDFCONV_ACCESS_TOKEN`，并置于反向代理（HTTPS）之后。
- 服务会处理任意上传文件，CLI 工具历史上有过解析漏洞 CVE；请勿在无隔离的主机上对不可信用户开放。更严格的场景建议给容器加 `read_only`、限制 CPU/内存，或使用 gVisor 等沙箱运行时。
- 输出文件保存在数据卷中，直到用户移除对应任务；如需自动过期，可在 `data/outputs` 上挂定时清理。
