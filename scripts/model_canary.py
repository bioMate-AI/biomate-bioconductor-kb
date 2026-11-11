#!/usr/bin/env python3
"""Daily model canary: run a tiny real inference on EVERY model in GET /api/models.

Why: on 2026-11-10 every hosted BioNeMo model on dev returned 410 Gone (NVIDIA
retired the NVCF pexec route) and nothing noticed — the Models panel was dead
while every unit test stayed green. This canary exercises the real path
(Node proxy -> Galaxy models_inference -> model backend) as the canonical E2E
fixture user and reports per-model status with the backend's real error.

Usage:
    python3 scripts/model_canary.py                     # against dev
    BIOMATE_URL=https://host python3 scripts/model_canary.py --json out.json

Env:
    BIOMATE_URL            default https://dev-public.biomate.ai
    E2E_FIXTURE_PASSWORD   else ~/.config/biomate/e2e_fixture_password
    E2E_TEST_TOKEN         default biomate-e2e-bypass-token-dev-only
    CANARY_ONLY            optional comma list of model ids to restrict to

Exit code: 0 if every model completed with a real payload, 1 otherwise,
2 on harness errors (login / catalog unreachable). Standard library only.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = os.environ.get("BIOMATE_URL", "https://dev-public.biomate.ai").rstrip("/")
EMAIL = "lifeifei163361@163.com"
E2E_TOKEN = os.environ.get("E2E_TEST_TOKEN", "biomate-e2e-bypass-token-dev-only")

PROTEIN = "MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQ"  # 33 aa
DNA = "ACGTACGTAGCTAGCTAGCATCGATCG"
SMILES = ["CC(=O)Oc1ccccc1C(=O)O", "CN1C=NC2=C1C(=O)N(C(=O)N2C)C"]


def _password() -> str:
    pw = os.environ.get("E2E_FIXTURE_PASSWORD")
    if pw:
        return pw
    f = Path.home() / ".config" / "biomate" / "e2e_fixture_password"
    if f.exists():
        return f.read_text().strip()
    raise SystemExit("ERROR: set E2E_FIXTURE_PASSWORD or create ~/.config/biomate/e2e_fixture_password")


def _req(method: str, path: str, token: str | None = None, body: dict | None = None, timeout: int = 60):
    headers = {"x-e2e-test-token": E2E_TOKEN, "Accept": "application/json"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            status = r.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        status = e.code
    try:
        return status, json.loads(raw)
    except ValueError:
        return status, {"_raw": raw[:300]}


def _inputs_for(model: dict) -> dict:
    fam = (model.get("family") or "").lower()
    mid = model.get("id", "")
    if fam == "structure":
        return {"sequence": PROTEIN}
    if fam == "genomic" or "evo2" in mid:
        return {"sequence": DNA, "num_tokens": 16}
    return {"smiles": SMILES}


def _check_payload(model: dict, inputs: dict, res: dict) -> str | None:
    """Return None when the payload is real, else a reason."""
    fam = (model.get("family") or "").lower()
    if fam == "structure":
        if not str(res.get("structureFileRef") or "").endswith((".cif", ".pdb")):
            return "no structure file reference"
        plddt = res.get("plddt") or []
        if len(plddt) != len(inputs["sequence"]):
            return f"pLDDT length {len(plddt)} != sequence length {len(inputs['sequence'])}"
        return None
    if fam == "genomic" or "evo2" in model.get("id", ""):
        iv = ((res.get("tracks") or [{}])[0].get("intervals") or [{}])[0]
        if not iv or iv.get("end", 0) - iv.get("start", 0) <= 0:
            return "no generated region in tracks"
        return None
    # chemical / custom scorers: any non-empty ranked result counts.
    if not any(isinstance(v, list) and v for k, v in res.items() if k not in ("flagged",)):
        return "empty result payload"
    return None


def run_one(token: str, model: dict) -> dict:
    mid = model["id"]
    inputs = _inputs_for(model)
    t0 = time.time()
    status, body = _req("POST", f"/api/models/{urllib.parse.quote(mid, safe='')}/infer", token, {"inputs": inputs}, timeout=420)
    row = {"id": mid, "name": model.get("name"), "family": model.get("family"), "http": status}
    if status >= 400 or "run_id" not in body:
        row.update(status="error", error=f"infer HTTP {status}: {json.dumps(body)[:300]}")
        return row
    run_id = body["run_id"]
    res: dict = {}
    for _ in range(60):
        _, res = _req("GET", f"/api/inference/{run_id}/result", token)
        if res.get("status") != "running":
            break
        time.sleep(5)
    row["seconds"] = round(time.time() - t0, 1)
    row["run_id"] = run_id
    if res.get("status") != "completed":
        row.update(status=res.get("status") or "unknown", error=str(res.get("error") or res)[:400])
        return row
    reason = _check_payload(model, inputs, res)
    row.update(status="ok" if reason is None else "bad_payload", error=reason)
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--json", help="write per-model results to this file")
    args = ap.parse_args()

    status, body = _req("POST", "/api/auth/login", body={"email": EMAIL, "password": _password()})
    token = body.get("token") or body.get("accessToken")
    if status != 200 or not token:
        print(f"ERROR: login failed HTTP {status}: {json.dumps(body)[:200]}", file=sys.stderr)
        return 2
    status, models = _req("GET", "/api/models", token)
    if status != 200 or not isinstance(models, list):
        print(f"ERROR: GET /api/models HTTP {status}: {json.dumps(models)[:300]}", file=sys.stderr)
        return 2
    only = {m.strip() for m in os.environ.get("CANARY_ONLY", "").split(",") if m.strip()}
    if only:
        models = [m for m in models if m.get("id") in only]
    if not models:
        print("ERROR: the model catalog is empty", file=sys.stderr)
        return 2

    rows = [run_one(token, m) for m in models]
    print(f"\nModel canary — {BASE} — {time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
    print(f"{'STATUS':<12} {'MODEL':<34} {'FAMILY':<10} {'SEC':>6}  ERROR")
    for r in rows:
        print(f"{r['status']:<12} {r['id']:<34} {str(r.get('family')):<10} {str(r.get('seconds', '')):>6}  {r.get('error') or ''}")
    bad = [r for r in rows if r["status"] != "ok"]
    print(f"\n{len(rows) - len(bad)}/{len(rows)} models OK")
    if args.json:
        Path(args.json).write_text(json.dumps({"base": BASE, "results": rows}, indent=2))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as fh:
            fh.write(f"## Model canary — {BASE}\n\n| status | model | family | s | error |\n|---|---|---|---|---|\n")
            for r in rows:
                err = (r.get("error") or "").replace("|", "\\|").replace("\n", " ")
                fh.write(f"| {r['status']} | `{r['id']}` | {r.get('family')} | {r.get('seconds', '')} | {err} |\n")
            fh.write(f"\n**{len(rows) - len(bad)}/{len(rows)} models OK**\n")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
