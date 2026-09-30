import asyncio
import signal


def install_shutdown_handler() -> None:
    loop = asyncio.get_running_loop()
    task = asyncio.current_task()
    if task is None:
        return
    try:
        loop.add_signal_handler(signal.SIGTERM, task.cancel)
    except (NotImplementedError, RuntimeError, ValueError):
        pass
