"""
routes/stream.py
GET /api/stream/<run_id>  — Server-Sent Events log stream
"""

from flask import Blueprint, Response

from backend.sse_manager import sse_manager

stream_bp = Blueprint("stream", __name__)


@stream_bp.route("/stream/<run_id>")
def stream_logs(run_id: str):
    """SSE endpoint that streams real-time Robot Framework log lines.

    The browser opens an EventSource to this URL after receiving a run_id.
    Each event has the shape:
        { message, level, timestamp, run_id }

    The stream ends with a DONE-level event when execution finishes.
    """

    def generate():
        import json
        # Initial connection acknowledgement
        yield (
            "data: "
            + json.dumps({"message": "Connected to log stream.", "level": "INFO"})
            + "\n\n"
        )
        yield from sse_manager.event_stream(run_id)

    return Response(
        generate(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control":   "no-cache",
            "X-Accel-Buffering": "no",   # Disable nginx buffering
            "Connection":      "keep-alive",
        },
    )
