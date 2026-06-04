#!/usr/bin/env python3
"""Re-poll a completed ZINC600 ADMET Galaxy run and refresh triage."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
MANIFEST = PUB / "zinc600_screen/ZINC600_ADMET_MANIFEST.json"


def load_api_key() -> str:
    cfg = (ROOT / "backend/config/galaxy.yml").read_text(encoding="utf-8")
    m = re.search(r"bootstrap_admin_api_key:\s*(\S+)", cfg)
    return m.group(1)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", default="")
    args = ap.parse_args()
    run_id = args.run_id
    if not run_id and MANIFEST.is_file():
        run_id = json.loads(MANIFEST.read_text()).get("run_id", "")
    if not run_id:
        raise SystemExit("No run_id")

    key = load_api_key()
    req = urllib.request.Request(
        f"http://127.0.0.1:8081/api/nextflow/status/{run_id}",
        headers={"X-API-Key": key},
    )
    status = json.loads(urllib.request.urlopen(req, timeout=120).read())
    print("status", status.get("status"), "files", len(status.get("s3_output_files") or []))

    # Rebuild via run_zinc600_top20_admet merge path
    import sys

    sys.path.insert(0, str(ROOT / "research/anti-virus/scripts"))
    from run_zinc600_top20_admet import (  # noqa: E402
        download_admet_json,
        load_merged_admet,
        top_hits,
        write_triage,
    )
    from parse_admet_result_text import parse_admet_text  # noqa: E402
    from datetime import datetime, timezone

    cache = PUB / "zinc600_screen/admet/cache"
    text = download_admet_json(status, cache)
    by_smi = load_merged_admet()
    if text:
        by_smi.update(parse_admet_text(text))
    hits = top_hits(20)
    n_lib = len(json.loads((PUB / "zinc150_screen/vina/docking_autodock_vina_results.json").read_text()).get("results") or [])
    write_triage(hits, by_smi, n_lib)
    out = PUB / "zinc600_screen/admet/predict_admet_properties_results.json"
    out.write_text(
        json.dumps(
            {
                "success": True,
                "merged_at": datetime.now(timezone.utc).isoformat(),
                "run_id": run_id,
                "by_smiles": by_smi,
                "result": text or "",
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    covered = sum(1 for h in hits if h["smiles"] in by_smi)
    print(f"ADMET coverage: {covered}/20 top hits")


if __name__ == "__main__":
    main()
