"""本地开发启动器：python run.py [--port 8765]

相比直接 uvicorn 的额外能力：向进程发送 SIGUSR1 可打印所有协程任务栈，
用于排查卡住的转换任务。
"""
import argparse
import asyncio
import faulthandler
import signal


async def stack_dumper():
    while True:
        await asyncio.sleep(10)
        for t in asyncio.all_tasks():
            if t is not asyncio.current_task() and not t.done():
                print(f"\n===== TASK STACK {t.get_name()} =====", flush=True)
                t.print_stack(limit=8)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--dump-signal", action="store_true",
                        help="启用 SIGUSR1 任务栈转储（调试用）")
    args = parser.parse_args()

    if args.dump_signal:
        faulthandler.register(signal.SIGUSR1)

    import uvicorn
    from app.main import app

    if args.dump_signal:
        @app.on_event("startup")
        async def _start_stack_dumper():
            asyncio.create_task(stack_dumper())

    uvicorn.run(app, host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
