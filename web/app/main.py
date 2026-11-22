"""FastAPI 入口 —— 路由、上传、SSE、静态页面。"""
import asyncio
import json
import re
import uuid
from pathlib import Path
from typing import Optional

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

from .catalog import CATEGORIES, TYPES_BY_KEY, type_brief
from .config import ACCESS_TOKEN, DATA_DIR, DEEPSEEK_API_KEY, OUTPUT_DIR, UPLOAD_LIMIT_MB, WEB_DIR
from .orchestrator import orchestrator
from .tools import INSTALL_INFO, find_tool

app = FastAPI(title="PDF Converter Web", version="1.0.0")


# ── 可选访问令牌 ──

async def require_token(request: Request):
    if not ACCESS_TOKEN:
        return
    token = request.headers.get("X-Access-Token") or request.query_params.get("token")
    if token != ACCESS_TOKEN:
        raise HTTPException(status_code=401, detail="访问令牌无效")


@app.on_event("startup")
async def startup():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    orchestrator.start()


@app.on_event("shutdown")
async def shutdown():
    await orchestrator.stop()


# ── 工具与类型目录 ──

def tool_status() -> dict:
    names = ["pdftoppm", "pdftotext", "qpdf", "gs", "soffice", "tesseract"]
    status = {name: bool(find_tool(name)) for name in names}
    try:
        import playwright  # noqa: F401
        status["playwright"] = True
    except ImportError:
        status["playwright"] = False
    return status


@app.get("/api/health")
async def health():
    return {"ok": True}


@app.get("/api/tools")
async def api_tools(_: None = Depends(require_token)):
    return {"tools": tool_status(), "hasServerKey": bool(DEEPSEEK_API_KEY),
            "install": INSTALL_INFO}


@app.get("/api/types")
async def api_types(_: None = Depends(require_token)):
    status = tool_status()
    result = []
    for cat_key, _ in CATEGORIES:
        for t in TYPES_BY_KEY.values():
            if t.category == cat_key:
                result.append(type_brief(t, status, bool(DEEPSEEK_API_KEY)))
    return {"categories": [{"key": k, "display": d} for k, d in CATEGORIES], "types": result}


# ── 任务 ──

_SAFE_NAME = re.compile(r"[\\/:*?\"<>|\x00-\x1f]")


def _sanitize(name: str) -> str:
    name = _SAFE_NAME.sub("_", Path(name).name).strip() or "file"
    return name[:150]


@app.post("/api/jobs")
async def create_job(request: Request,
                     type: str = Form(...),
                     params: str = Form("{}"),
                     files: list[UploadFile] = File(...),
                     _: None = Depends(require_token)):
    t = TYPES_BY_KEY.get(type)
    if not t:
        raise HTTPException(400, "未知的转换类型")
    if not files or not files[0].filename:
        raise HTTPException(400, "请选择文件")

    file_list = [f for f in files if f.filename]
    # 扩展名前置校验：给出清晰错误，而不是让转换引擎在半路失败
    if t.accept:
        for f in file_list:
            ext = Path(f.filename or "").suffix.lower()
            if ext not in t.accept:
                raise HTTPException(
                    400,
                    f"{t.display} 不支持 {ext or '无扩展名'} 文件（支持: {' '.join(t.accept)}）")
    if len(file_list) > 1 and not t.multiple:
        raise HTTPException(400, f"{t.display} 只支持单个文件")
    if type == "mergePDF" and len(file_list) < 2:
        raise HTTPException(400, "合并 PDF 至少需要 2 个文件")

    try:
        params_dict = json.loads(params) if params else {}
    except json.JSONDecodeError:
        raise HTTPException(400, "参数格式错误")

    job_id = uuid.uuid4().hex
    job_dir = OUTPUT_DIR / job_id
    inputs_dir = job_dir / "inputs"
    inputs_dir.mkdir(parents=True, exist_ok=True)

    limit = UPLOAD_LIMIT_MB * 1024 * 1024
    total = 0
    saved: list[Path] = []
    names: list[str] = []
    for f in file_list:
        safe = _sanitize(f.filename)
        dest = inputs_dir / safe
        size = 0
        with dest.open("wb") as w:
            while chunk := await f.read(1024 * 1024):
                size += len(chunk)
                total += size  # 所有文件累计
                if total > limit:
                    w.close()
                    raise HTTPException(413, f"上传超过大小限制（{UPLOAD_LIMIT_MB} MB）")
                w.write(chunk)
        saved.append(dest)
        names.append(safe)

    job = orchestrator.enqueue(type, t.display, names, params_dict, saved, job_id=job_id)
    return JSONResponse({"id": job.id, "status": job.status})


@app.get("/api/jobs")
async def list_jobs(_: None = Depends(require_token)):
    return orchestrator.snapshot()


@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str, _: None = Depends(require_token)):
    job = orchestrator.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "任务不存在")
    return job.to_json()


@app.delete("/api/jobs/{job_id}")
async def delete_job(job_id: str, _: None = Depends(require_token)):
    orchestrator.remove(job_id)
    return {"ok": True}


@app.post("/api/jobs/clear-completed")
async def clear_completed(_: None = Depends(require_token)):
    return {"removed": orchestrator.clear_completed()}


@app.post("/api/jobs/clear-all")
async def clear_all(_: None = Depends(require_token)):
    return {"removed": orchestrator.clear_all()}


@app.post("/api/jobs/{job_id}/retry")
async def retry_job(job_id: str, _: None = Depends(require_token)):
    job = orchestrator.retry(job_id)
    if not job:
        raise HTTPException(404, "任务不存在")
    return {"id": job.id}


@app.get("/api/jobs/{job_id}/files/{name}")
async def download(job_id: str, name: str, _: None = Depends(require_token)):
    path = orchestrator.job_output_file(job_id, name)
    if not path:
        raise HTTPException(404, "文件不存在或任务未完成")
    return FileResponse(path, filename=name)


# ── SSE 实时推送 ──

@app.get("/api/events")
async def events(request: Request, _: None = Depends(require_token)):
    queue = orchestrator.subscribe()

    async def gen():
        try:
            yield f"data: {json.dumps(orchestrator.snapshot(), ensure_ascii=False)}\n\n"
            while True:
                if await request.is_disconnected():
                    break
                try:
                    snapshot = await asyncio.wait_for(queue.get(), timeout=15)
                    yield f"data: {snapshot}\n\n"
                except asyncio.TimeoutError:
                    yield ": heartbeat\n\n"  # 保活
        finally:
            orchestrator.unsubscribe(queue)

    return StreamingResponse(gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache",
                                      "X-Accel-Buffering": "no"})


# ── 静态页面 ──

app.mount("/static", StaticFiles(directory=WEB_DIR / "static"), name="static")


@app.get("/")
async def index():
    return FileResponse(WEB_DIR / "static" / "index.html")


# PWA：sw.js 必须从根作用域提供（/static/sw.js 的作用域只有 /static/*，
# 无法控制页面本身）；manifest 同样放根路径。
@app.get("/sw.js")
async def service_worker():
    return FileResponse(WEB_DIR / "static" / "sw.js",
                        media_type="application/javascript",
                        headers={"Service-Worker-Allowed": "/"})


@app.get("/manifest.webmanifest")
async def webmanifest():
    return FileResponse(WEB_DIR / "static" / "manifest.webmanifest",
                        media_type="application/manifest+json")
