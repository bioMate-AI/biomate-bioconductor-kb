#!/usr/bin/env python3
"""ADMET triage table for top Vina hits (ZINC150 subset or full ZINC600 screen)."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUBLICATION = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
sys.path.insert(0, str(ROOT / "research/anti-virus/scripts"))
from parse_admet_result_text import parse_admet_text, triage_fields  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, default=PUBLICATION)
    ap.add_argument("--top-n", type=int, default=20)
    ap.add_argument(
        "--docking-json",
        type=Path,
        default=None,
        help="Default: publication zinc150_screen/vina/docking_autodock_vina_results.json",
    )
    ap.add_argument("--admet-json", type=Path, default=None)
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    pub = args.publication_run.resolve()
    dock_path = args.docking_json or (pub / "zinc150_screen/vina/docking_autodock_vina_results.json")
    admet_path = args.admet_json or (pub / "zinc600_screen/admet/predict_admet_properties_results.json")
    if not admet_path.is_file():
        admet_path = pub / "zinc150_screen/admet/predict_admet_properties_results.json"
    out_path = args.out or (pub / "zinc600_screen/ZINC600_TOP20_ADMET_TRIAGE.md")

    dock = json.loads(dock_path.read_text(encoding="utf-8"))
    n_lib = len(dock.get("results", []))
    label = "ZINC600" if n_lib >= 500 else "ZINC150"
    admet_by_smi: dict = {}
    if admet_path.is_file():
        raw = json.loads(admet_path.read_text(encoding="utf-8"))
        if raw.get("by_smiles"):
            admet_by_smi.update(raw["by_smiles"])
        text = raw.get("result") or ""
        if isinstance(text, str):
            admet_by_smi.update(parse_admet_text(text))
        for row in raw.get("results", raw.get("compounds", [])):
            sm = row.get("smiles") or row.get("SMILES")
            if sm:
                admet_by_smi[sm] = row

    hits = sorted(
        [r for r in dock.get("results", []) if r.get("best_affinity_kcal_mol") is not None],
        key=lambda r: float(r.get("best_affinity_kcal_mol", 0)),
    )[: args.top_n]

    lines = [
        f"# {label} — top {args.top_n} Vina hits ADMET triage",
        "",
        f"_Screen size: **{n_lib}** compounds docked (9P3I top pocket)._",
        "",
        "| Rank | Vina (kcal/mol) | hERG | DILI | BBB | SMILES |",
        "|------|-----------------|------|------|-----|--------|",
    ]
    for i, hit in enumerate(hits, 1):
        smi = hit.get("smiles", "")
        tf = triage_fields(admet_by_smi.get(smi, {}))
        vina = hit.get("best_affinity_kcal_mol", "—")
        lines.append(f"| {i} | {vina} | {tf['hERG']} | {tf['DILI']} | {tf['BBB']} | `{smi[:40]}…` |")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out_path} ({len(hits)} rows from {n_lib} docked)")


if __name__ == "__main__":
    main()
