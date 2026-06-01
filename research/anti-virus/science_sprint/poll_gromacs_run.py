#!/usr/bin/env python3
"""Poll a Nextflow run via Galaxy API and update track_inh_md manifest until terminal."""

from __future__ import annotations

import json
import re
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "research/anti-virus/science_sprint/runs/20260528T033751Z/track_inh_md/manifest.json"
RUN_ID = "9bf5f9a2-2420-4189-888b-d455909a614d"
API_URL = "http://127.0.0.1:8081"
POLL_SEC = 120
TIMEOUT_SEC = 72 * 3600
TERMINAL = {"completed", "succeeded", "failed", "cancelled", "error"}


def load_api_key() -> str:
    gal = ROOT / "backend/config/galaxy.yml"
    text = gal.read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", text)
    if not m:
        raise SystemExit("bootstrap_admin_api_key missing in galaxy.yml")
    return m.group(1).strip()


def get_status(api_key: str) -> dict:
    req = urllib.request.Request(
        f"{API_URL}/api/nextflow/status/{RUN_ID}",
        headers={"X-API-Key": api_key},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def log(msg: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    log_path = ROOT / "research/anti-virus/science_sprint/logs/20260528T033751Z_gromacs_poll.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def main() -> None:
    api_key = load_api_key()
    deadline = time.time() + TIMEOUT_SEC
    poll_n = 0
    while time.time() < deadline:
        poll_n += 1
        try:
            st = get_status(api_key)
        except Exception as exc:  # noqa: BLE001
            log(f"poll {poll_n:04d} ERROR {exc!r}")
            time.sleep(POLL_SEC)
            continue

        status = st.get("status", "")
        prog = st.get("progressPercent")
        dur = st.get("duration_s")
        procs = st.get("processes") or []
        proc_line = "; ".join(
            f"{p.get('name')}={p.get('status')}" for p in procs[:6]
        )
        log(f"poll {poll_n:04d} status={status!r} progress={prog}% duration_s={dur} [{proc_line}]")

        if MANIFEST.is_file():
            mf = json.loads(MANIFEST.read_text(encoding="utf-8"))
            mf["last_polled_at"] = datetime.now(timezone.utc).isoformat()
            mf["latest_status"] = {
                "status": status,
                "progressPercent": prog,
                "duration_s": dur,
                "processes": procs,
            }
            if status in TERMINAL:
                mf["status"] = "succeeded" if status in ("completed", "succeeded") else "failed"
                mf["finished_at"] = datetime.now(timezone.utc).isoformat()
            MANIFEST.write_text(json.dumps(mf, indent=2), encoding="utf-8")

        if status in TERMINAL:
            log(f"terminal status={status!r} returncode={st.get('returncode')}")
            sys.exit(0 if status in ("completed", "succeeded") else 1)

        time.sleep(POLL_SEC)

    log("TIMEOUT waiting for terminal status")
    sys.exit(2)


if __name__ == "__main__":
    main()
