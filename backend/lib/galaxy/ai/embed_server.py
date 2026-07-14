"""
Shared embedding server — single process owning both SentenceTransformer models.

Gunicorn starts this via on_starting() before forking workers. Each worker
connects via embed_client.py. Net saving: ~1.5 GB (both models × 3 extra workers).

Protocol: newline-delimited JSON over a Unix socket.
  Request:  {"op": "encode_wf",    "query": "deseq2"}
  Request:  {"op": "encode_chain", "query": "deseq2"}
  Request:  {"op": "ping"}
  Response: {"ok": true, "vec": [0.1, ...]}   (vec omitted for ping)
  Response: {"ok": false, "err": "..."}
"""

import json
import logging
import os
import socket
import struct
import subprocess
import sys
import threading
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

SOCKET_PATH = "/tmp/biomate_embed.sock"
_WF_MODEL_NAME = "BAAI/bge-small-en-v1.5"
_CHAIN_MODEL_NAME = "all-MiniLM-L6-v2"


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


def _handle_client(conn: socket.socket, wf_model, chain_model) -> None:
    try:
        while True:
            data = _recv_msg(conn)
            if data is None:
                break
            try:
                req = json.loads(data)
                op = req.get("op")
                if op == "ping":
                    _send_msg(conn, json.dumps({"ok": True}).encode())
                elif op == "encode_wf":
                    vec = wf_model.encode([req["query"]], convert_to_numpy=True)[0]
                    _send_msg(conn, json.dumps({"ok": True, "vec": vec.tolist()}).encode())
                elif op == "encode_chain":
                    vec = chain_model.encode([req["query"]], convert_to_numpy=True)[0]
                    _send_msg(conn, json.dumps({"ok": True, "vec": vec.tolist()}).encode())
                elif op == "encode_batch_chain":
                    texts = req["texts"]
                    vecs = chain_model.encode(texts, convert_to_numpy=True)
                    _send_msg(conn, json.dumps({"ok": True, "vecs": vecs.tolist()}).encode())
                else:
                    _send_msg(conn, json.dumps({"ok": False, "err": f"unknown op: {op}"}).encode())
            except Exception as exc:
                try:
                    _send_msg(conn, json.dumps({"ok": False, "err": str(exc)}).encode())
                except Exception:
                    break
    finally:
        try:
            conn.close()
        except Exception:
            pass


def run_server() -> None:
    """Main server loop — call from __main__ only."""
    import numpy as np  # noqa: F401 — verify numpy is importable
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("[EmbedServer] sentence_transformers not available; exiting", file=sys.stderr)
        sys.exit(1)

    log.info("[EmbedServer] Loading models %s + %s …", _WF_MODEL_NAME, _CHAIN_MODEL_NAME)
    wf_model = SentenceTransformer(_WF_MODEL_NAME, device="cpu", local_files_only=True)
    chain_model = SentenceTransformer(_CHAIN_MODEL_NAME, device="cpu", local_files_only=True)
    log.info("[EmbedServer] Models loaded. Starting socket at %s", SOCKET_PATH)

    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass

    server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server_sock.bind(SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o666)
    server_sock.listen(32)
    log.info("[EmbedServer] Listening on %s", SOCKET_PATH)

    while True:
        try:
            conn, _ = server_sock.accept()
            t = threading.Thread(target=_handle_client, args=(conn, wf_model, chain_model), daemon=True)
            t.start()
        except Exception as exc:
            log.error("[EmbedServer] accept error: %s", exc)


def start_subprocess() -> Optional[subprocess.Popen]:
    """
    Start the embed server as a subprocess of the calling process.
    Called from gunicorn's on_starting() hook — runs in master before workers fork.
    Returns the Popen handle (or None on error).
    """
    if os.environ.get("BIOMATE_EMBED_SERVER_DISABLE"):
        return None

    if _socket_alive():
        log.info("[EmbedServer] Socket already alive; skipping start")
        return None

    server_script = str(Path(__file__).resolve())
    python = sys.executable
    env = dict(os.environ)
    env["PYTHONPATH"] = str(Path(__file__).resolve().parents[3])  # .../lib

    log.info("[EmbedServer] Starting embed server subprocess …")
    proc = subprocess.Popen(
        [python, server_script],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    # Wait up to 60 s for the socket to appear
    import time
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if _socket_alive():
            log.info("[EmbedServer] Socket ready (pid=%d)", proc.pid)
            return proc
        time.sleep(0.5)
    log.warning("[EmbedServer] Socket did not appear within 60 s; continuing without it")
    return proc


def _socket_alive() -> bool:
    """Return True if the socket file exists and accepts a ping."""
    if not os.path.exists(SOCKET_PATH):
        return False
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(1.0)
            s.connect(SOCKET_PATH)
            _send_msg(s, json.dumps({"op": "ping"}).encode())
            data = _recv_msg(s)
            if data:
                resp = json.loads(data)
                return resp.get("ok", False)
    except Exception:
        pass
    return False


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [EmbedServer] %(levelname)s %(message)s",
    )
    run_server()
