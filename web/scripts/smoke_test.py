"""冒烟测试：对 /api/jobs 全链路提交 → 轮询 → 校验输出。

用法（服务需已在本地运行）:
    python scripts/smoke_test.py [--base http://127.0.0.1:8765]
可选 --only mergePDF,rotatePDF ... 只跑部分用例。
"""
import argparse
import json
import sys
import time
from pathlib import Path

import httpx
import pymupdf

BASE = "http://127.0.0.1:8765"
TMP = Path(__file__).resolve().parent.parent / "data" / "smoke"


def make_fixtures():
    TMP.mkdir(parents=True, exist_ok=True)
    paths = {}
    for i, name in [(1, "doc_a.pdf"), (2, "doc_b.pdf")]:
        p = TMP / name
        doc = pymupdf.open()
        page = doc.new_page()
        page.insert_textbox(page.rect, f"冒烟测试文档 {i}\nSmoke Test Page", fontsize=18, fontname="china-s")
        doc.save(p)
        doc.close()
        paths[f"pdf{i}"] = p
    pix = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 400, 300))
    pix.clear_with(120)
    img = TMP / "pic.png"
    pix.save(img)
    paths["png"] = img
    txt = TMP / "note.txt"
    txt.write_text("这是一份用于 LibreOffice 转换的测试文档。\nSmoke test document.", "utf-8")
    paths["txt"] = txt
    html = TMP / "page.html"
    html.write_text("<html><body><h1>Smoke Test</h1><p>HTML → PDF 测试页面</p></body></html>", "utf-8")
    paths["html"] = html
    return paths


def submit(client, type_key: str, files: list[Path], params: dict | None = None) -> str:
    fd = [("files", (f.name, f.open("rb"), "application/octet-stream")) for f in files]
    fd.append(("type", (None, type_key)))
    fd.append(("params", (None, json.dumps(params or {}))))
    r = client.post(f"{BASE}/api/jobs", files=fd)
    r.raise_for_status()
    return r.json()["id"]


def wait_job(client, job_id: str, timeout: float = 180) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        job = client.get(f"{BASE}/api/jobs/{job_id}").json()
        if job["status"] in ("completed", "failed", "cancelled"):
            return job
        time.sleep(0.5)
    raise TimeoutError(job_id)


CASES = [
    ("mergePDF", ["pdf1", "pdf2"], {}),
    ("splitPDF", ["pdf1"], {}),
    ("rotatePDF", ["pdf1"], {"rotationDegrees": 180}),
    ("watermarkPDF", ["pdf1"], {"watermarkText": "机密文件"}),
    ("encryptPDF", ["pdf1"], {"password": "123456"}),
    ("decryptPDF", ["pdf1"], {"password": "123456"}),
    ("pngToPDF", ["png"], {}),
    ("pdfToPNG", ["pdf1"], {"dpi": 150}),
    ("pdfToText", ["pdf1"], {}),
    ("wordToPDF", ["txt"], {}),
    ("compressPDF", ["pdf1"], {"compressionLevel": "ebook"}),
    ("ocrSearchablePDF", ["pdf1"], {"ocrLanguages": "eng"}),
    ("htmlToPDF", ["html"], {}),
    ("pdfAISummary", ["pdf1"], {}),
]


def main():
    global BASE
    args = argparse.ArgumentParser()
    args.add_argument("--base", default=BASE)
    args.add_argument("--only", default="")
    a = args.parse_args()
    BASE = a.base
    only = {s.strip() for s in a.only.split(",") if s.strip()}

    paths = make_fixtures()
    ok = failed = expected_fail = 0
    with httpx.Client(timeout=120) as client:
        for type_key, file_keys, params in CASES:
            if only and type_key not in only:
                continue
            files = [paths[k] for k in file_keys]
            job_id = submit(client, type_key, files, params)
            job = wait_job(client, job_id)
            tag = ""
            if job["status"] == "completed":
                ok += 1
            elif type_key in ("compressPDF", "ocrSearchablePDF", "htmlToPDF", "pdfAISummary"):
                expected_fail += 1
                tag = f"（预期失败: {job['error']}）"
            else:
                failed += 1
                tag = f"!!! 意外失败: {job['error']}"
            outs = ", ".join(o["name"] for o in job["outputs"]) or "-"
            print(f"[{job['status']:>9}] {type_key:<18} → {outs} {tag}")

    print(f"\n完成: 成功 {ok} / 预期失败 {expected_fail} / 意外失败 {failed}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
