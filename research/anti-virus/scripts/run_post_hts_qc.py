#!/usr/bin/env python3
"""Post-HTS QC: purchasability lookup + ensemble docking (publication top-20, generative top-5).

  python3 research/anti-virus/scripts/run_post_hts_qc.py
  nohup python3 -u research/anti-virus/scripts/run_post_hts_qc.py > /tmp/post_hts_qc.log 2>&1 &
"""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
ENSEMBLE = ROOT / "research/anti-virus/science_sprint/track_inh_ensemble_docking.py"
RECONCILE = ROOT / "research/anti-virus/scripts/reconcile_ensemble_docking.py"
LOOKUP = ROOT / "research/anti-virus/scripts/lookup_publication_zinc_top20.py"
SUMMARIZE_GEN = ROOT / "research/anti-virus/scripts/summarize_generative_inh01_docking.py"
BASELINE_RUN = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"
PUB_DOCK = PUB / "publication_zinc/vina/docking_autodock_vina_results.json"
GEN_DOCK = PUB / "reinvent_inh01/vina/docking_autodock_vina_results.json"
QC_DIR = PUB / "post_hts_qc"


def log(msg: str) -> None:
    print(msg, flush=True)


def run(cmd: list[str]) -> None:
    log("$ " + " ".join(cmd))
    subprocess.run(cmd, cwd=ROOT, check=True)


def write_baseline_subset(
    src: Path,
    out: Path,
    top_n: int,
    *,
    exclude_control_tranche: bool = False,
    meta_tsv: Path | None = None,
) -> Path:
    data = json.loads(src.read_text(encoding="utf-8"))
    meta: dict[str, str] = {}
    if meta_tsv and meta_tsv.is_file():
        for i, line in enumerate(meta_tsv.read_text(encoding="utf-8").splitlines()):
            if i == 0 or not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                meta[parts[1]] = parts[2]

    ok = [r for r in data.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    ok.sort(key=lambda r: float(r["best_affinity_kcal_mol"]))
    picked: list[dict] = []
    for r in ok:
        sm = r["smiles"]
        if exclude_control_tranche and meta.get(sm) == "control":
            continue
        picked.append(r)
        if len(picked) >= top_n:
            break

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"results": picked}, indent=2) + "\n", encoding="utf-8")
    log(f"Baseline subset {len(picked)} compounds → {out}")
    return out


def main() -> None:
    QC_DIR.mkdir(parents=True, exist_ok=True)
    log("=== Post-HTS QC ===")

    run([sys.executable, str(LOOKUP), "--top-n", "20"])
    if SUMMARIZE_GEN.is_file():
        run([sys.executable, str(SUMMARIZE_GEN)])

    pub_baseline = write_baseline_subset(
        PUB_DOCK,
        QC_DIR / "publication_top20_baseline.json",
        20,
        exclude_control_tranche=True,
        meta_tsv=PUB / "publication_zinc/dock_set.tsv",
    )
    gen_baseline = write_baseline_subset(
        GEN_DOCK,
        QC_DIR / "generative_top5_baseline.json",
        5,
    )

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    run(
        [
            sys.executable,
            "-u",
            str(ENSEMBLE),
            "--baseline-docking-json",
            str(pub_baseline),
            "--user-id",
            f"pub-top20-{ts[:8]}",
        ]
    )
    # ensemble writes to science_sprint/runs/<ts>/track_inh_ensemble — move/reconcile
    latest = sorted((ROOT / "research/anti-virus/science_sprint/runs").glob("*/track_inh_ensemble"))[-1]
    run([sys.executable, str(RECONCILE), str(latest)])

    run(
        [
            sys.executable,
            "-u",
            str(ENSEMBLE),
            "--baseline-docking-json",
            str(gen_baseline),
            "--user-id",
            f"gen-top5-{ts[:8]}",
        ]
    )
    latest_gen = sorted((ROOT / "research/anti-virus/science_sprint/runs").glob("*/track_inh_ensemble"))[-1]
    run([sys.executable, str(RECONCILE), str(latest_gen)])

    report = [
        "# Post-HTS QC report",
        "",
        f"_Generated: {datetime.now(timezone.utc).isoformat()}_",
        "",
        f"- Purchasability: `{LOOKUP.relative_to(ROOT)}` output",
        f"- Publication ensemble: `{latest.relative_to(ROOT)}`",
        f"- Generative ensemble: `{latest_gen.relative_to(ROOT)}`",
    ]
    (QC_DIR / "POST_HTS_QC_REPORT.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    log("Done.")


if __name__ == "__main__":
    main()
