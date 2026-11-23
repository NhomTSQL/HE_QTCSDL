import threading
import time
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class EventHub:
    """Thread-safe in-memory pub/sub pulse for SSE real-time UI updates."""

    def __init__(self):
        self._cond = threading.Condition()
        self._seq = 0
        self._last = {"type": "init", "ts": time.time()}

    def publish(self, event_type: str, **data):
        with self._cond:
            self._seq += 1
            self._last = {"seq": self._seq, "type": event_type, "ts": time.time(), **data}
            self._cond.notify_all()
            return self._seq

    def snapshot(self):
        with self._cond:
            return self._seq, dict(self._last)

    def wait_next(self, seen_seq: int, timeout: float = 15.0):
        with self._cond:
            if self._seq == seen_seq:
                self._cond.wait(timeout=timeout)
            return self._seq, dict(self._last)


event_hub = EventHub()

