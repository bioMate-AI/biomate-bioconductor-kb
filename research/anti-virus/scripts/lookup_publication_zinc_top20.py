#!/usr/bin/env python3
"""Purchasability / identity for publication_zinc top-N (uses dock_set.tsv ZINC IDs).

  python3 research/anti-virus/scripts/lookup_publication_zinc_top20.py --top-n 20
"""
from __future__ import annotations

import argparse
import csv
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
DOCK_JSON = PUB / "publication_zinc/vina/docking_autodock_vina_results.json"
DOCK_SET = PUB / "publication_zinc/dock_set.tsv"
OUT_JSON = PUB / "publication_zinc/PUBLICATION_ZINC_TOP20_PURCHASABILITY.json"
OUT_MD = PUB / "publication_zinc/PUBLICATION_ZINC_TOP20_PURCHASABILITY.md"

CONTROL_PREFIX = "CONTROL_"


def pubchem_lookup(smiles: str) -> dict:
    url = (
        "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles/"
        + urllib.parse.quote(smiles, safe="")
        + "/cids/JSON"
    )
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "BioMate-zinc-lookup/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        cids = data.get("IdentifierList", {}).get("CID") or []
        return {"pubchem_cid": cids[0] if cids else None}
    except Exception as e:
        return {"pubchem_cid": None, "error": str(e)}


def load_meta(tsv: Path) -> dict[str, dict[str, str]]:
    meta: dict[str, dict[str, str]] = {}
    for i, line in enumerate(tsv.read_text(encoding="utf-8").splitlines()):
        if i == 0 or not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        meta[parts[1]] = {"zinc_id": parts[0], "tranche": parts[2]}
    return meta


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--top-n", type=int, default=20)
    ap.add_argument("--exclude-controls", action="store_true", default=True)
    ap.add_argument("--skip-pubchem", action="store_true")
    args = ap.parse_args()

    dock = json.loads(DOCK_JSON.read_text(encoding="utf-8"))
    meta = load_meta(DOCK_SET)
    ok = [r for r in dock.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    ok.sort(key=lambda r: float(r["best_affinity_kcal_mol"]))

    rows: list[dict] = []
    for hit in ok:
        sm = hit["smiles"]
        m = meta.get(sm, {})
        if args.exclude_controls and m.get("tranche") == "control":
            continue
        if m.get("zinc_id", "").startswith(CONTROL_PREFIX):
            continue
        row = {
            "smiles": sm,
            "vina_kcal_mol": float(hit["best_affinity_kcal_mol"]),
            "zinc_substance_id": m.get("zinc_id"),
            "tranche": m.get("tranche"),
        }
        if not args.skip_pubchem:
            row.update(pubchem_lookup(sm))
        rows.append(row)
        if len(rows) >= args.top_n:
            break

    payload = {
        "looked_up_at": datetime.now(timezone.utc).isoformat(),
        "source": str(DOCK_JSON.relative_to(ROOT)),
        "top_n": len(rows),
        "exclude_controls": args.exclude_controls,
        "results": [{**r, "rank": i} for i, r in enumerate(rows, 1)],
    }
    OUT_JSON.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = [
        f"# Publication ZINC top-{len(rows)} — purchasability / identity",
        "",
        f"_Updated: {payload['looked_up_at']}_",
        "",
        "ZINC substance IDs from `publication_zinc/dock_set.tsv` (multi-tranche build).",
        "",
        "| Rank | Vina | ZINC ID | Tranche | PubChem CID | SMILES |",
        "| ---: | ---: | --- | --- | ---: | --- |",
    ]
    for r in payload["results"]:
        pc = r.get("pubchem_cid") or "—"
        lines.append(
            f"| {r['rank']} | {r['vina_kcal_mol']:.3f} | {r.get('zinc_substance_id') or '—'} | "
            f"{r.get('tranche') or '—'} | {pc} | `{r['smiles'][:40]}` |"
        )
    OUT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT_JSON} ({len(rows)} hits)")


if __name__ == "__main__":
    main()
