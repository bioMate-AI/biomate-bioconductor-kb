#!/usr/bin/env python3
"""Summarize publication_zinc Vina results: top-N, controls, vs blog-tier ZINC600.

Run after docking completes (or on partial progress):

  python3 research/anti-virus/scripts/summarize_publication_zinc_docking.py
  python3 research/anti-virus/scripts/summarize_publication_zinc_docking.py --top-n 50
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from rdkit import Chem
from rdkit.Chem import Descriptors, QED


ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
DOCK_JSON = PUB / "publication_zinc/vina/docking_autodock_vina_results.json"
PROGRESS = PUB / "publication_zinc/vina/dock_progress.json"
DOCK_SET = PUB / "publication_zinc/dock_set.tsv"
MANIFEST = PUB / "publication_zinc/manifest.json"
Z600_JSON = PUB / "zinc150_screen/vina/docking_autodock_vina_results.json"
OUT = PUB / "publication_zinc/vina/PUBLICATION_ZINC_DOCK_SUMMARY.md"

CONTROL_SMILES = {
    "N=C(N)NC(=O)c1nccnc1N": "INH-01",
    "N=C(N)NC(=O)NC(=O)NC(=N)N": "Z600-R1",
    "CC(C)(C)c1ccc(C(O)c2ccc(Cl)cc2)cc1": "umifenovir",
    "C1CC(=O)NC(=O)C1N": "favipiravir",
    "NC(=O)c1nc(C=C(C)CO)c(C=O)[nH]1": "ribavirin",
    "CCOC(=O)C1=C[C@@H](OC(CC)CC)[C@H](NC(C)=O)[C@H](O)[C@H]1O": "oseltamivir",
}


def load_meta(tsv: Path) -> dict[str, dict[str, str]]:
    meta: dict[str, dict[str, str]] = {}
    for i, line in enumerate(tsv.read_text(encoding="utf-8").splitlines()):
        if i == 0 or not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        sid, smi, tranche = parts[0], parts[1], parts[2]
        meta[smi] = {"zinc_id": sid, "tranche": tranche, "features": parts[3] if len(parts) > 3 else ""}
    return meta


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--top-n", type=int, default=20)
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()

    if not DOCK_JSON.is_file():
        raise SystemExit(f"Missing {DOCK_JSON}")

    dock = json.loads(DOCK_JSON.read_text(encoding="utf-8"))
    meta = load_meta(DOCK_SET) if DOCK_SET.is_file() else {}
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.is_file() else {}
    progress = json.loads(PROGRESS.read_text(encoding="utf-8")) if PROGRESS.is_file() else {}

    results = dock.get("results") or []
    ok = [r for r in results if r.get("best_affinity_kcal_mol") is not None]
    failed = len(results) - len(ok)
    top = sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"]))[: args.top_n]

    z600_best = None
    if Z600_JSON.is_file():
        z600 = json.loads(Z600_JSON.read_text(encoding="utf-8"))
        z600_ok = [r for r in z600.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
        if z600_ok:
            z600_best = min(z600_ok, key=lambda r: float(r["best_affinity_kcal_mol"]))

    docked = progress.get("docked", len(results))
    total = progress.get("total", manifest.get("dock_set_count", len(results)))
    complete = docked >= total

    lines = [
        "# Publication ZINC — Vina docking summary",
        "",
        f"_Generated: {datetime.now(timezone.utc).isoformat()}_",
        f"_Progress: **{docked}/{total}** docked"
        + (" — **COMPLETE**" if complete else " — **IN PROGRESS**")
        + f"; {failed} failed/empty in merged JSON._",
        "",
        "## Library funnel (build)",
        "",
        "| Stage | Count |",
        "|-------|------:|",
        f"| Raw tranche union | {manifest.get('raw_union_unique', '—')} |",
        f"| Drug-like | {manifest.get('druglike_count', '—')} |",
        f"| Pharmacophore pass (≥{manifest.get('min_features', 3)}) | {manifest.get('pharmacophore_pass_count', '—')} |",
        f"| Dock set | {manifest.get('dock_set_count', total)} |",
        "",
        "**Tranches:** " + ", ".join(manifest.get("tranche_urls", [])) if manifest.get("tranche_urls") else "",
        "",
        "## Controls (injected)",
        "",
        "| Label | Vina (kcal/mol) | Status |",
        "|-------|-----------------|--------|",
    ]

    for smi, label in CONTROL_SMILES.items():
        hit = next((r for r in ok if r.get("smiles") == smi), None)
        if hit:
            lines.append(f"| {label} | {float(hit['best_affinity_kcal_mol']):.3f} | docked |")
        else:
            lines.append(f"| {label} | — | pending |")

    lines.extend(
        [
            "",
            f"## Top {args.top_n} hits (publication deck)",
            "",
            "| Rank | Vina | ZINC ID | Tranche | MW | QED | SMILES |",
            "|------|------|---------|---------|----|-----|--------|",
        ]
    )

    for i, hit in enumerate(top, 1):
        sm = hit["smiles"]
        m = meta.get(sm, {})
        mol = Chem.MolFromSmiles(sm)
        mw = f"{Descriptors.MolWt(mol):.1f}" if mol else "—"
        qed = f"{QED.qed(mol):.3f}" if mol else "—"
        label = CONTROL_SMILES.get(sm, "")
        note = f" **{label}**" if label else ""
        lines.append(
            f"| {i} | {float(hit['best_affinity_kcal_mol']):.3f} | "
            f"{m.get('zinc_id', '—')} | {m.get('tranche', '—')} | {mw} | {qed} | `{sm}`{note} |"
        )

    if top:
        best = top[0]
        lines.extend(
            [
                "",
                "## Headline comparison",
                "",
                f"- **Publication deck best (so far):** {float(best['best_affinity_kcal_mol']):.3f} kcal/mol",
            ]
        )
        if z600_best:
            lines.append(
                f"- **Blog-tier ZINC600 best:** {float(z600_best['best_affinity_kcal_mol']):.3f} kcal/mol "
                f"(`{z600_best['smiles'][:40]}…`)"
            )
        inh = next((r for r in ok if r.get("smiles") == "N=C(N)NC(=O)c1nccnc1N"), None)
        if inh:
            rank = sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"])).index(inh) + 1
            lines.append(
                f"- **INH-01 rank:** #{rank} of {len(ok)} docked "
                f"({float(inh['best_affinity_kcal_mol']):.3f} kcal/mol)"
            )

    lines.extend(
        [
            "",
            "## Interpretation (do not overclaim)",
            "",
            "- Publication deck is **target-informed** (pharmacophore + multi-tranche); blog 600 AAAC is **not**.",
            "- Vina scores remain **weak in silico hits**; no antiviral potency claim.",
            "- After full dock: run ensemble + pose QC on top-20; compare purchasability via `lookup_zinc_purchasability.py`.",
            "",
            f"**Artifacts:** `{DOCK_JSON.relative_to(ROOT)}`, `{PROGRESS.relative_to(ROOT) if PROGRESS.is_file() else 'dock_progress.json'}`",
        ]
    )

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out} ({len(ok)} scored / {docked} progress)")


if __name__ == "__main__":
    main()
