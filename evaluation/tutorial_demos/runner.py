"""Tutorial-demo validation runner.

Submits the canonical prompt to BioMate dev, polls the run to completion,
downloads outputs, and invokes the per-domain validator. Emits a JSON
verdict consumable by the voiceover generator and CI.

Usage:
    python -m evaluation.tutorial_demos.runner <domain_key>

where <domain_key> matches a top-level key under `demos:` in
gold_standards.yaml (e.g. transcriptomics).
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import requests
import yaml

ROOT = Path(__file__).resolve().parent
REGISTRY = ROOT / "gold_standards.yaml"
RESULTS_DIR = ROOT / "results"
RESULTS_DIR.mkdir(exist_ok=True)

DEV_BASE = os.environ.get("BIOMATE_DEV_BASE", "https://dev-public.biomate.ai")
FIXTURE_EMAIL = "lifeifei163361@163.com"
FIXTURE_PASSWORD = os.environ.get("E2E_FIXTURE_PASSWORD")
E2E_TOKEN = os.environ.get("E2E_TEST_TOKEN", "biomate-e2e-bypass-token-dev-only")
POLL_INTERVAL_S = 30
RUN_TIMEOUT_S = 60 * 90  # 90 min cap per run


def load_registry() -> dict[str, Any]:
    with REGISTRY.open() as fh:
        return yaml.safe_load(fh)["demos"]


def login() -> str:
    if not FIXTURE_PASSWORD:
        raise SystemExit("E2E_FIXTURE_PASSWORD env not set")
    r = requests.post(
        f"{DEV_BASE}/api/auth/login",
        json={"email": FIXTURE_EMAIL, "password": FIXTURE_PASSWORD},
        headers={"x-e2e-test-token": E2E_TOKEN},
        timeout=30,
    )
    r.raise_for_status()
    token = r.json().get("token")
    if not token:
        raise SystemExit(f"login returned no token: {r.text[:200]}")
    return token


def submit_prompt(token: str, prompt: str, s3_inputs: str) -> str:
    """Send the demo prompt over SSE, return invocationId from workflowMetadata.

    /api/chat/stream is an SSE endpoint that emits `delta` events; the
    workflow card arrives as a `workflowMetadata` payload near the end of
    the stream. We accumulate events until we see invocationId or the
    stream closes, then return.
    """
    full_prompt = f"{prompt}\n\nInputs (S3 prefix): {s3_inputs}\nPlease run the workflow."
    body = {
        "message": full_prompt,
        "confirm_run": True,
        "context": {"sessionId": f"tutorial-demo-{int(time.time())}"},
    }
    with requests.post(
        f"{DEV_BASE}/api/chat/stream",
        headers={"Authorization": f"Bearer {token}",
                 "x-e2e-test-token": E2E_TOKEN,
                 "Content-Type": "application/json",
                 "Accept": "text/event-stream"},
        json=body,
        stream=True,
        timeout=600,
    ) as r:
        r.raise_for_status()
        run_id: str | None = None
        buf = ""
        for line in r.iter_lines(decode_unicode=True):
            if line is None:
                continue
            if line.startswith("data:"):
                payload = line[5:].strip()
                if not payload or payload == "[DONE]":
                    continue
                try:
                    evt = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                wm = evt.get("workflowMetadata") or evt.get("workflow_metadata")
                if wm:
                    run_id = wm.get("invocationId") or wm.get("runId") or run_id
                run_id = (evt.get("invocationId") or evt.get("runId") or run_id)
                if run_id:
                    break
            else:
                buf += line + "\n"
        if not run_id:
            raise SystemExit(
                f"no invocationId in SSE stream; first 1KB:\n{buf[:1000]}"
            )
        return run_id


def poll(token: str, run_id: str) -> dict[str, Any]:
    deadline = time.monotonic() + RUN_TIMEOUT_S
    while time.monotonic() < deadline:
        r = requests.get(
            f"{DEV_BASE}/api/workflows/runs/{run_id}",
            headers={"Authorization": f"Bearer {token}",
                     "x-e2e-test-token": E2E_TOKEN},
            timeout=30,
        )
        if r.status_code == 200:
            doc = r.json()
            status = doc.get("status")
            if status in {"completed", "failed", "error"}:
                return doc
        time.sleep(POLL_INTERVAL_S)
    raise SystemExit(f"run {run_id} timed out after {RUN_TIMEOUT_S}s")


def run_validator(domain_key: str, run_doc: dict[str, Any]) -> dict[str, Any]:
    """Dispatch to evaluation/tutorial_demos/<domain_key>.py:validate()."""
    mod = __import__(f"evaluation.tutorial_demos.{domain_key}", fromlist=["validate"])
    return mod.validate(run_doc)


def main(domain_key: str) -> None:
    registry = load_registry()
    if domain_key not in registry:
        raise SystemExit(f"unknown domain {domain_key}; have {list(registry)}")
    demo = registry[domain_key]

    print(f"[runner] demo={demo['slug']} chain={demo['chain']}")
    token = login()
    run_id = submit_prompt(token, demo["prompt"], demo["s3_inputs"])
    print(f"[runner] submitted run_id={run_id}; polling…")
    run_doc = poll(token, run_id)
    print(f"[runner] run {run_id} reached status={run_doc.get('status')}")

    verdict = run_validator(domain_key, run_doc)
    verdict.update({
        "slug": demo["slug"],
        "chain": demo["chain"],
        "anchor_publication": demo["gold"]["anchor"],
        "run_id": run_id,
    })
    out = RESULTS_DIR / f"{domain_key}.json"
    out.write_text(json.dumps(verdict, indent=2))
    print(json.dumps(verdict, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python -m evaluation.tutorial_demos.runner <domain_key>")
    main(sys.argv[1])
