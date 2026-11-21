"""任务调度 —— 桌面版 JobOrchestrator（Swift actor）的 asyncio 移植。

行为对齐：
- 队列 + 并发上限（maxConcurrent，默认 2）
- pending / running / completed / failed / cancelled 状态机
- 取消：pending 直接移除；running 通过 Task.cancel() 中断
- 状态广播：对应 broadcastUpdate，这里推给 SSE 订阅者
- 任务目录：桌面版是 $TMPDIR/PDFConverter/<uuid>，这里是 data/outputs/<uuid>
"""
import asyncio
import json
import shutil
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from .config import MAX_CONCURRENT, OUTPUT_DIR
from .engines import ENGINES, JobContext
from .tools import ConversionError, ToolMissing


@dataclass
class Job:
    id: str
    type: str
    display: str
    input_names: list[str]
    params: dict
    created_at: float = field(default_factory=time.time)
    status: str = "pending"       # pending/running/completed/failed/cancelled
    progress: float = 0.0
    outputs: list[dict] = field(default_factory=list)  # [{name, size}]
    error: str | None = None
    details: str | None = None
    task: asyncio.Task | None = field(default=None, repr=False)

    def to_json(self) -> dict:
        return {
            "id": self.id,
            "type": self.type,
            "display": self.display,
            "inputNames": self.input_names,
            "status": self.status,
            "progress": round(self.progress, 3),
            "outputs": self.outputs,
            "error": self.error,
            "details": self.details,
            "createdAt": self.created_at,
        }


class Orchestrator:
    def __init__(self):
        self.jobs: dict[str, Job] = {}
        self.queue: asyncio.Queue[str] = asyncio.Queue()
        self.subscribers: set[asyncio.Queue] = set()
        self._workers: list[asyncio.Task] = []

    # ── 启动 / 停止 ──

    def start(self):
        for i in range(MAX_CONCURRENT):
            self._workers.append(asyncio.create_task(self._worker(i)))

    async def stop(self):
        for w in self._workers:
            w.cancel()
        await asyncio.gather(*self._workers, return_exceptions=True)

    # ── SSE 订阅 ──

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=64)
        self.subscribers.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue):
        self.subscribers.discard(q)

    def broadcast(self):
        snapshot = json.dumps(self.snapshot(), ensure_ascii=False)
        for q in list(self.subscribers):
            try:
                q.put_nowait(snapshot)
            except asyncio.QueueFull:
                pass

    def snapshot(self) -> list[dict]:
        return [j.to_json() for j in
                sorted(self.jobs.values(), key=lambda j: j.created_at, reverse=True)]

    # ── 任务操作 ──

    def enqueue(self, type_key: str, display: str, input_names: list[str],
                params: dict, input_paths: list[Path],
                job_id: str | None = None) -> Job:
        """job_id：调用方已按此 ID 建好目录并存好输入文件时必须传入，
        否则 worker 会去一个空目录找输入（对齐 bug 教训）。"""
        job = Job(id=job_id or uuid.uuid4().hex, type=type_key, display=display,
                  input_names=input_names, params=params)
        self.jobs[job.id] = job
        self.queue.put_nowait(job.id)
        self.broadcast()
        return job

    def cancel(self, job_id: str):
        job = self.jobs.get(job_id)
        if not job:
            return
        if job.status == "pending":
            job.status = "cancelled"
            self.broadcast()
        elif job.status == "running" and job.task:
            job.task.cancel()

    def remove(self, job_id: str):
        job = self.jobs.pop(job_id, None)
        if job:
            if job.status == "running" and job.task:
                job.task.cancel()
            shutil.rmtree(self._job_dir(job.id), ignore_errors=True)
            self.broadcast()

    def clear_completed(self) -> int:
        targets = [j.id for j in self.jobs.values()
                   if j.status in ("completed", "failed", "cancelled")]
        for jid in targets:
            self.remove(jid)
        return len(targets)

    def clear_all(self) -> int:
        count = len(self.jobs)
        for jid in list(self.jobs):
            self.remove(jid)
        return count

    def retry(self, job_id: str) -> Job | None:
        """对应 retryJob：以原参数重新入队一份新任务（输入文件从旧任务目录拷贝）。"""
        old = self.jobs.get(job_id)
        if not old:
            return None
        old_dir = self._job_dir(job_id) / "inputs"
        new_dir = self._job_dir(uuid.uuid4().hex) / "inputs"
        new_dir.mkdir(parents=True, exist_ok=True)
        paths = []
        for name in old.input_names:
            src = old_dir / name
            if src.exists():
                dst = new_dir / name
                shutil.copy2(src, dst)
                paths.append(dst)
        job = self.enqueue(old.type, old.display, list(old.input_names),
                           dict(old.params), paths)
        return job

    def job_output_file(self, job_id: str, name: str) -> Path | None:
        """下载定位：只允许访问已登记的输出文件（防目录穿越）。"""
        job = self.jobs.get(job_id)
        if not job or job.status != "completed":
            return None
        if name not in [o["name"] for o in job.outputs]:
            return None
        path = self._job_dir(job_id) / "out" / name
        return path if path.exists() else None

    # ── 内部 ──

    @staticmethod
    def _job_dir(job_id: str) -> Path:
        d = OUTPUT_DIR / job_id
        (d / "inputs").mkdir(parents=True, exist_ok=True)
        return d

    async def _worker(self, index: int):
        while True:
            job_id = await self.queue.get()
            job = self.jobs.get(job_id)
            if not job or job.status != "pending":
                continue  # 已被取消/移除
            # 外层保险层：调度器自身的任何意外都不允许杀死 worker
            # （一旦 worker 退出，其后所有任务都会永久卡在 pending）
            try:
                await self._process(job)
            except asyncio.CancelledError:
                job.status = "cancelled"
                self.broadcast()
            except Exception as e:
                job.status, job.error = "failed", f"调度器内部错误: {type(e).__name__}"
                job.details = str(e)
                self.broadcast()
            finally:
                job.task = None

    async def _process(self, job: Job):
        job.status = "running"
        job.progress = 0.05
        job.task = asyncio.current_task()
        self.broadcast()

        job_dir = self._job_dir(job.id)
        inputs = [p for p in (job_dir / "inputs").iterdir() if p.is_file()]

        async def progress(value: float):
            job.progress = max(job.progress, min(1.0, value))
            self.broadcast()

        ctx = JobContext(job_id=job.id, type=job.type, inputs=inputs,
                         work_dir=job_dir, params=dict(job.params),
                         progress=progress)

        try:
            engine = ENGINES[job.type]
            outputs = await engine(ctx)
            job.outputs = [{"name": p.name, "size": p.stat().st_size} for p in outputs]
            job.status = "completed"
            job.progress = 1.0
        except (ConversionError, ToolMissing) as e:
            job.status, job.error = "failed", e.message
            job.details = getattr(e, "details", None)
        except asyncio.CancelledError:
            job.status = "cancelled"
        except Exception as e:  # 未知异常兜底
            job.status, job.error = "failed", f"内部错误: {type(e).__name__}"
            job.details = str(e)
        finally:
            self.broadcast()


orchestrator = Orchestrator()
