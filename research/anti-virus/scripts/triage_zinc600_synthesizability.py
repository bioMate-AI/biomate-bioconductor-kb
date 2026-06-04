#!/usr/bin/env python3
"""RDKit SA-score synthesizability triage for ZINC600 top-N Vina hits."""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

from rdkit import Chem
from rdkit.Chem import Descriptors, QED, RDConfig

sys.path.insert(0, os.path.join(RDConfig.RDContribDir, "SA_Score"))
import sascorer  # noqa: E402


def sa_tier(sa: float) -> str:
    if sa <= 3:
        return "EASY"
    if sa <= 5:
        return "MODERATE"
    if sa <= 7:
        return "HARD"
    return "VERY_HARD"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--publication-run",
        default="research/anti-virus/runs/publication_20260528T223525Z",
        help="Publication run directory",
    )
    ap.add_argument("--top-n", type=int, default=20)
    ap.add_argument("--out", default="", help="Output markdown path")
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[3]
    pub = root / args.publication_run
    dock_path = pub / "zinc150_screen/vina/docking_autodock_vina_results.json"
    out_path = Path(args.out) if args.out else pub / "zinc600_screen/ZINC600_TOP20_SYNTHESIZABILITY.md"

    dock = json.loads(dock_path.read_text(encoding="utf-8"))
    ok = [r for r in dock.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    top = sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"]))[: args.top_n]
    n_lib = len(dock.get("results") or [])

    rows = []
    for i, hit in enumerate(top, 1):
        sm = hit["smiles"]
        mol = Chem.MolFromSmiles(sm)
        if mol is None:
            continue
        sa = sascorer.calculateScore(mol)
        rows.append(
            {
                "rank": i,
                "vina": float(hit["best_affinity_kcal_mol"]),
                "smiles": sm,
                "sa": round(sa, 2),
                "tier": sa_tier(sa),
                "qed": round(QED.qed(mol), 3),
                "mw": round(Descriptors.MolWt(mol), 1),
            }
        )

    easy = sum(1 for r in rows if r["tier"] == "EASY")
    moderate = sum(1 for r in rows if r["tier"] == "MODERATE")
    hard = len(rows) - easy - moderate

    lines = [
        f"# ZINC600 — top {args.top_n} Vina hits synthesizability triage",
        "",
        f"_Screen size: **{n_lib}** compounds docked (9P3I top pocket)._",
        f"_Generated: {datetime.now(timezone.utc).isoformat()}_",
        "",
        "**Method:** RDKit **SA Score** via `rdkit.Contrib.SA_Score.sascorer`. Lower = easier.",
        "",
        "| Tier | SA range | Interpretation |",
        "|------|----------|----------------|",
        "| EASY | ≤ 3 | Straightforward synthesis |",
        "| MODERATE | 3–5 | Typical medicinal chemistry |",
        "| HARD | 5–7 | Challenging |",
        "| VERY_HARD | > 7 | Likely difficult / specialist |",
        "",
        "**Not run:** SynCraft retrosynthesis. SA score is a **proxy only**.",
        "",
        "| Rank | Vina (kcal/mol) | SA | Tier | QED | MW | SMILES |",
        "|------|-----------------|----|------|-----|-----|--------|",
    ]
    for r in rows:
        note = " (INH-01)" if r["smiles"] == "N=C(N)NC(=O)c1nccnc1N" else ""
        bold_sa = f"**{r['sa']:.2f}**" if r["tier"] == "EASY" else f"{r['sa']:.2f}"
        bold_tier = f"**{r['tier']}**" if r["tier"] == "EASY" else r["tier"]
        lines.append(
            f"| {r['rank']} | {r['vina']:.3f} | {bold_sa} | {bold_tier} | {r['qed']:.3f} | {r['mw']:.1f} | `{r['smiles']}`{note} |"
        )

    lines.extend(
        [
            "",
            "## Summary",
            "",
            "| Metric | Value |",
            "|--------|-------|",
            f"| Top {args.top_n} with SA ≤ 5 | **{sum(1 for r in rows if r['sa'] <= 5)}/{len(rows)}** |",
            f"| EASY (SA ≤ 3) | {easy} |",
            f"| MODERATE (3 < SA ≤ 5) | {moderate} |",
            f"| HARD / VERY_HARD | {hard} |",
            "",
        ]
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out_path} ({len(rows)} compounds)")


if __name__ == "__main__":
    main()
