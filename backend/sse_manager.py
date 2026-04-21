"""
backend/sse_manager.py
Server-Sent Events manager for real-time test execution log streaming.

Each test run gets its own queue identified by run_id.
The Flask SSE endpoint reads from this queue and forwards messages
to the browser using the text/event-stream MIME type.
"""

import json
import queue
import threading
from datetime import datetime
from typing import Iterator


class SSEManager:
    """Thread-safe SSE queue manager.

    Usage:
        # Producer side (test runner thread):
        sse_manager.create_run(run_id)
        sse_manager.push_log("Starting…", "INFO", run_id)
        sse_manager.end_run(run_id)

        # Consumer side (Flask SSE route):
        yield from sse_manager.event_stream(run_id)
    """

    def __init__(self) -> None:
        self._queues: dict[str, queue.Queue] = {}
        self._lock = threading.Lock()
        self.active_run_id: str | None = None

    # ── Lifecycle ────────────────────────────────────────────

    def create_run(self, run_id: str) -> None:
        """Register a new queue for *run_id*."""
        with self._lock:
            self._queues[run_id] = queue.Queue()
            self.active_run_id = run_id

    def end_run(self, run_id: str) -> None:
        """Signal the consumer that the run is complete."""
        with self._lock:
            if run_id in self._queues:
                self._queues[run_id].put("__END__")

    def cleanup_run(self, run_id: str) -> None:
        """Remove the queue for *run_id* to free memory."""
        with self._lock:
            self._queues.pop(run_id, None)

    # ── Producer API ─────────────────────────────────────────

    def push_log(
        self,
        message: str,
        level: str = "INFO",
        run_id: str | None = None,
    ) -> None:
        """Push a log entry into the queue for *run_id* (defaults to active run)."""
        target = run_id or self.active_run_id
        if not target or target not in self._queues:
            return

        payload = json.dumps(
            {
                "message": message,
                "level": level,
                "timestamp": datetime.now().strftime("%H:%M:%S"),
                "run_id": target,
            }
        )
        self._queues[target].put(payload)

    # ── Consumer API ─────────────────────────────────────────

    def event_stream(self, run_id: str) -> Iterator[str]:
        """Yield SSE-formatted strings until *run_id* ends.

        Each yielded value is a complete SSE "data: …\\n\\n" frame.
        A keep-alive comment is sent every 25 s so proxies don't time out.
        """
        if run_id not in self._queues:
            yield f'data: {json.dumps({"message": "Run not found", "level": "ERROR"})}\n\n'
            return

        q = self._queues[run_id]
        while True:
            try:
                item = q.get(timeout=25)
                if item == "__END__":
                    done_payload = json.dumps(
                        {"message": "Execution finished.", "level": "DONE"}
                    )
                    yield f"data: {done_payload}\n\n"
                    break
                yield f"data: {item}\n\n"
            except queue.Empty:
                # Keep-alive comment — ignored by browsers but prevents idle timeout
                yield ": keepalive\n\n"


# ── Singleton ────────────────────────────────────────────────
sse_manager = SSEManager()
