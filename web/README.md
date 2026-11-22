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

## PWA：安装到手机桌面

Web 版同时是一个可安装的 PWA（manifest + Service Worker）：

- **Android Chrome**：访问后自动弹出安装提示，或点侧边栏「📲 安装到手机桌面」；
  安装后桌面出现独立图标、全屏 standalone 运行、应用外壳可离线打开（转换需联网）
- **iOS Safari**：分享 → 「添加到主屏幕」（apple-touch-icon 已内置）
- **要求安全上下文**：HTTPS 或 localhost。局域网 IP + HTTP 访问功能完整但 Chrome 不提供安装入口
- SW 缓存策略：页面网络优先（断网回退缓存的壳）、静态资源缓存优先、`/api/*` 一律直通

## Windows 上使用

**作为客户端**：B/S 架构与操作系统无关——服务器跑在任何地方（Linux / macOS / NAS / 云主机），
Windows 上用浏览器打开服务地址即可，无需安装任何东西。

**把服务端跑在 Windows 上**（不装 Docker 时的原生方案）：

1. 安装 Python 3.10+，`pip install -r requirements.txt`
2. 安装转换工具（服务会自动识别 PATH 与常见安装目录，Windows 上的 `gswin64c` 也能识别）：
   - Poppler：[poppler-windows release](https://github.com/oschwartz10612/poppler-windows/releases) 解压后把 `bin` 加入 PATH
   - qpdf：[官网下载](https://qpdf.readthedocs.io/en/stable/installation.html)
   - Ghostscript：[官网安装包](https://www.ghostscript.com/download.html)
   - Tesseract：[UB-Mannheim 安装包](https://github.com/UB-Mannheim/tesseract/wiki)（勾选中文语言包）
   - LibreOffice：[官网安装](https://www.libreoffice.org/download/)
3. `python run.py --port 8000`（局域网访问加 `--host 0.0.0.0`）

也可以直接用 **Docker Desktop / WSL2** 跑镜像，效果与 Linux 相同。

## 安卓客户端（PWA 安装到桌面）

Web 版本身就是**可安装的 PWA**——安卓 Chrome 访问后会提示「安装应用」，或点侧边栏
「📲 安装到手机桌面」按钮。安装后桌面出现独立图标、全屏运行（无浏览器地址栏）、
断网时仍能打开界面（转换需联网）。iOS 上通过 Safari「分享 → 添加到主屏幕」获得同样体验。

实现：`static/manifest.webmanifest`（图标 192/512 + maskable、standalone 显示模式）
+ `static/sw.js`（应用外壳缓存：页面与静态资源离线可用，API 一律直通网络不缓存）。

> ⚠️ PWA 安装要求安全上下文（HTTPS 或 localhost）。局域网 IP + HTTP 访问时功能完整，
> 但 Chrome 不提供安装入口——公网部署请套 HTTPS。

## 浏览器兼容性

| 浏览器 | 支持情况 |
|--------|---------|
| Chrome / Edge 80+ | ✅ 实测通过 |
| Safari 15.4+（macOS 12.3+ / iOS 15.4） | ✅ 实测通过（WebKit） |
| Firefox 90+ | ✅ 代码全兼容（标准 HTML/CSS/JS，无框架依赖） |
| IE | ❌ 不支持 |

细节说明：
- **客户端零依赖**：纯标准 HTML/CSS/JS 单页，无框架、无构建产物
- **局域网 HTTP 访问兼容**：非 HTTPS 环境下剪贴板 API 不可用，已自动降级为 execCommand 方案（复制安装命令等均可用）
- **旧浏览器降级**：不支持 `<dialog>` 的旧版浏览器（如 Safari < 15.4）自动降级为 open 属性弹层
- 手机端（iOS / Android 浏览器）已有专门的 ≤720px 响应式布局

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
