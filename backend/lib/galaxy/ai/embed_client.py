"""
Client for the shared embedding server (embed_server.py).

Drop-in replacement for SentenceTransformer.encode() in workers.
Falls back to None gracefully if the server is unavailable — callers
must handle None (FTS-only path).
"""

import json
import logging
import os
import socket
import struct
import threading
from typing import Optional, List

import numpy as np

log = logging.getLogger(__name__)

SOCKET_PATH = "/tmp/biomate_embed.sock"
_CONNECT_TIMEOUT = 0.5   # seconds — fast-fail if server is not up
_REQUEST_TIMEOUT = 5.0   # seconds per encode call


def _send_msg(conn: socket.socket, data: bytes) -> None:
    conn.sendall(struct.pack(">I", len(data)) + data)


def _recv_msg(conn: socket.socket) -> Optional[bytes]:
    raw = _recv_exact(conn, 4)
    if not raw:
        return None
    length = struct.unpack(">I", raw)[0]
    return _recv_exact(conn, length)


def _recv_exact(conn: socket.socket, n: int) -> Optional[bytes]:
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


class EmbeddingClient:
    """Thread-safe client for the embed server. One instance per worker is fine."""

    def __init__(self):
        self._lock = threading.Lock()
        self._sock: Optional[socket.socket] = None
        self._disabled = bool(os.environ.get("BIOMATE_EMBED_SERVER_DISABLE"))

    def _connect(self) -> bool:
        if self._disabled:
            return False
        if self._sock is not None:
            return True
        if not os.path.exists(SOCKET_PATH):
            return False
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(_CONNECT_TIMEOUT)
            s.connect(SOCKET_PATH)
            s.settimeout(_REQUEST_TIMEOUT)
            self._sock = s
            return True
        except Exception as exc:
            log.debug("[EmbedClient] connect failed: %s", exc)
            return False

    def _call(self, req: dict) -> Optional[dict]:
        with self._lock:
            if not self._connect():
                return None
            try:
                data = json.dumps(req).encode()
                _send_msg(self._sock, data)
                resp_data = _recv_msg(self._sock)
                if resp_data is None:
                    self._sock = None
                    return None
                return json.loads(resp_data)
            except Exception as exc:
                log.debug("[EmbedClient] call error: %s", exc)
                try:
                    self._sock.close()
                except Exception:
                    pass
                self._sock = None
                return None

    def encode_wf(self, query: str) -> Optional[np.ndarray]:
        """Encode a query using the workflow embedding model (BAAI/bge-small-en-v1.5)."""
        resp = self._call({"op": "encode_wf", "query": query})
        if resp and resp.get("ok") and resp.get("vec"):
            return np.array(resp["vec"], dtype=np.float32)
        return None

    def encode_chain(self, query: str) -> Optional[np.ndarray]:
        """Encode a query using the chain embedding model (all-MiniLM-L6-v2)."""
        resp = self._call({"op": "encode_chain", "query": query})
        if resp and resp.get("ok") and resp.get("vec"):
            return np.array(resp["vec"], dtype=np.float32)
        return None

    def encode_batch_chain(self, texts: List[str]) -> Optional[np.ndarray]:
        """Encode a batch of texts using the chain model — for building the chain index."""
        resp = self._call({"op": "encode_batch_chain", "texts": texts})
        if resp and resp.get("ok") and resp.get("vecs"):
            return np.array(resp["vecs"], dtype=np.float32)
        return None

    def available(self) -> bool:
        """Quick liveness check."""
        if self._disabled:
            return False
        resp = self._call({"op": "ping"})
        return bool(resp and resp.get("ok"))


# Module-level singleton — one per worker process.
_client: Optional[EmbeddingClient] = None
_client_lock = threading.Lock()


def get_client() -> EmbeddingClient:
    global _client
    if _client is None:
        with _client_lock:
            if _client is None:
                _client = EmbeddingClient()
    return _client
