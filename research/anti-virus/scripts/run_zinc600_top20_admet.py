#!/usr/bin/env python3
"""
Run ADMET-AI on ZINC600 top-N Vina hits and refresh triage table.

Merges with existing zinc150 ADMET text cache where SMILES overlap.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
DOCK = PUB / "zinc150_screen/vina/docking_autodock_vina_results.json"
LEGACY_ADMET = PUB / "zinc150_screen/admet/predict_admet_properties_results.json"
OUT_ADMET = PUB / "zinc600_screen/admet/predict_admet_properties_results.json"
OUT_TRIAGE = PUB / "zinc600_screen/ZINC600_TOP20_ADMET_TRIAGE.md"
PIPE = ROOT / "research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py"

sys.path.insert(0, str(ROOT / "research/anti-virus/scripts"))
from parse_admet_result_text import parse_admet_text, triage_fields  # noqa: E402


def load_api_key() -> str:
    cfg = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", cfg)
    if not m:
        raise SystemExit("No Galaxy API key in backend/config/galaxy.yml")
    return m.group(1)


def top_hits(n: int) -> list[dict[str, Any]]:
    data = json.loads(DOCK.read_text(encoding="utf-8"))
    ok = [r for r in data.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    return sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"]))[:n]


def load_merged_admet() -> dict[str, dict[str, Any]]:
    by_smi: dict[str, dict[str, Any]] = {}
    for path in (LEGACY_ADMET, OUT_ADMET):
        if not path.is_file():
            continue
        raw = json.loads(path.read_text(encoding="utf-8"))
        text = raw.get("result") or ""
        if isinstance(text, str) and text.strip():
            by_smi.update(parse_admet_text(text))
        for row in raw.get("results") or raw.get("compounds") or []:
            sm = row.get("smiles") or row.get("SMILES")
            if sm:
                by_smi[sm] = row
    return by_smi


def post_admet(api_url: str, key: str, smiles: list[str], user_id: str) -> dict[str, Any]:
    body = {
        "nextflow_path": "nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf",
        "parameters": {"smiles_list": json.dumps(smiles), "ADMET_model_type": "MPNN"},
        "compute_config": {"executor": "awsbatch", "s3_bucket": "biomate-nextflow-work"},
        "workflow_domain": "pharmacology",
        "user_id": user_id,
        "profile": "aws",
    }
    req = urllib.request.Request(
        f"{api_url.rstrip('/')}/api/nextflow/execute",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "X-API-Key": key},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return json.loads(resp.read().decode("utf-8"))


def poll_status(api_url: str, key: str, run_id: str, timeout: int = 1800) -> dict[str, Any]:
    import time

    deadline = time.time() + timeout
    last: dict[str, Any] = {}
    while time.time() < deadline:
        req = urllib.request.Request(
            f"{api_url.rstrip('/')}/api/nextflow/status/{run_id}",
            headers={"X-API-Key": key},
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            last = json.loads(resp.read().decode("utf-8"))
        if last.get("status") in {"succeeded", "completed", "failed", "cancelled", "error"}:
            return last
        time.sleep(20)
    last["_timeout"] = True
    return last


def download_admet_json(status: dict[str, Any], cache_dir: Path) -> str | None:
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = "predict_admet_properties_results.json"
    for item in status.get("s3_output_files") or []:
        if not isinstance(item, dict):
            continue
        uri = item.get("s3_uri") or ""
        if uri and ((item.get("filename") or "").lower() == target or uri.endswith("/" + target)):
            local = cache_dir / f"{status.get('run_id', 'run')[:8]}_{target}"
            if subprocess.run(["aws", "s3", "cp", uri, str(local)], check=False).returncode == 0:
                raw = json.loads(local.read_text(encoding="utf-8"))
                return raw.get("result") if isinstance(raw.get("result"), str) else json.dumps(raw)
    outdir = (status.get("outdir") or "").rstrip("/")
    if outdir.startswith("s3://"):
        for suffix in ("/run", ""):
            local = cache_dir / f"out_{suffix.strip('/') or 'root'}_{target}"
            uri = f"{outdir}{suffix}/{target}"
            if subprocess.run(["aws", "s3", "cp", uri, str(local)], check=False).returncode == 0:
                raw = json.loads(local.read_text(encoding="utf-8"))
                return raw.get("result") if isinstance(raw.get("result"), str) else json.dumps(raw)
    return None


def write_triage(hits: list[dict[str, Any]], by_smi: dict[str, dict[str, Any]], n_lib: int) -> None:
    lines = [
        "# ZINC600 — top 20 Vina hits ADMET triage",
        "",
        f"_Screen size: **{n_lib}** compounds docked (9P3I top pocket)._",
        "",
        "| Rank | Vina (kcal/mol) | hERG | DILI | BBB | SMILES |",
        "|------|-----------------|------|------|-----|--------|",
    ]
    for i, hit in enumerate(hits, 1):
        smi = hit.get("smiles", "")
        tf = triage_fields(by_smi.get(smi, {}))
        vina = hit.get("best_affinity_kcal_mol", "—")
        lines.append(
            f"| {i} | {vina} | {tf['hERG']} | {tf['DILI']} | {tf['BBB']} | `{smi[:40]}…` |"
        )
    OUT_TRIAGE.parent.mkdir(parents=True, exist_ok=True)
    OUT_TRIAGE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--top-n", type=int, default=20)
    ap.add_argument("--api-url", default="http://127.0.0.1:8081")
    ap.add_argument("--skip-submit", action="store_true", help="Only rebuild triage from cached ADMET")
    args = ap.parse_args()

    hits = top_hits(args.top_n)
    n_lib = len(json.loads(DOCK.read_text(encoding="utf-8")).get("results") or [])
    by_smi = load_merged_admet()
    missing = [h["smiles"] for h in hits if h["smiles"] not in by_smi]

    manifest: dict[str, Any] = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "top_n": args.top_n,
        "missing_before_run": len(missing),
        "missing_smiles": missing,
    }

    if missing and not args.skip_submit:
        key = load_api_key()
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        submit = post_admet(args.api_url, key, missing, f"zinc600-admet-{stamp[:8]}")
        run_id = submit.get("run_id")
        manifest["run_id"] = run_id
        manifest["submit"] = submit
        if not run_id:
            raise SystemExit(f"ADMET submit failed: {json.dumps(submit)[:500]}")
        print(f"ADMET submitted run_id={run_id} for {len(missing)} compounds")
        status = poll_status(args.api_url, key, run_id)
        manifest["status"] = status
        text = download_admet_json(status, PUB / "zinc600_screen/admet/cache")
        if text:
            by_smi.update(parse_admet_text(text))
            manifest["new_compounds_parsed"] = len(parse_admet_text(text))
        else:
            manifest["error"] = "Could not download ADMET JSON from S3"
            print("WARN:", manifest["error"])

    # Rebuild merged text blob for downstream tools
    merged_lines = ["ADMET-AI Predictions (ZINC600 top-N merge)\n" + "=" * 65 + "\n"]
    for h in hits:
        sm = h["smiles"]
        m = by_smi.get(sm)
        if not m:
            continue
        merged_lines.append(f"Compound: {sm}")
        for k, v in sorted(m.items()):
            if k == "smiles":
                continue
            merged_lines.append(f"  {k.replace('_', ' '):28s}: {v}")
        merged_lines.append("-" * 40 + "\n")

    OUT_ADMET.parent.mkdir(parents=True, exist_ok=True)
    OUT_ADMET.write_text(
        json.dumps(
            {
                "success": True,
                "function": "predict_admet_properties",
                "merged_at": datetime.now(timezone.utc).isoformat(),
                "n_compounds": len(by_smi),
                "result": "\n".join(merged_lines),
                "by_smiles": by_smi,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (PUB / "zinc600_screen/ZINC600_ADMET_MANIFEST.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    write_triage(hits, by_smi, n_lib)
    covered = sum(1 for h in hits if h["smiles"] in by_smi)
    print(f"Wrote {OUT_ADMET}")
    print(f"Wrote {OUT_TRIAGE} ({covered}/{len(hits)} top hits with ADMET)")


if __name__ == "__main__":
    main()
