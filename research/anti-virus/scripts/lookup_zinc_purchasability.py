#!/usr/bin/env python3
"""Look up catalog / identity for top Vina SMILES (multi-backend).

Backends (tried in order unless --backend restricts):
  1. **local_tranche** — exact SMILES match in the campaign ZINC20 2D tranche
     (files.docking.org; default AA/AAAC.smi, first 600 = publication library).
  2. **pubchem** — PUG REST SMILES → PubChem CID (+ InChIKey).
  3. **cartblanche** — ZINC22 CartBlanche API (often flaky; similarity fallback dist=3).

Usage:
  python3 research/anti-virus/scripts/lookup_zinc_purchasability.py \\
    --publication-run research/anti-virus/runs/publication_20260528T223525Z --top-n 5
"""
from __future__ import annotations

import argparse
import csv
import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
DEFAULT_TRANCHE_URL = "https://files.docking.org/2D/AA/AAAC.smi"
DEFAULT_LIBRARY_N = 600


def fetch_text(url: str, timeout: int = 120) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-zinc-lookup/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def load_local_tranche_index(
    tranche_url: str,
    *,
    max_compounds: int = DEFAULT_LIBRARY_N,
    cache_path: Path | None = None,
) -> dict[str, dict[str, str]]:
    """Map SMILES → {zinc_id, source_url} from ZINC20 2D tranche file."""
    if cache_path and cache_path.is_file():
        text = cache_path.read_text(encoding="utf-8")
    else:
        text = fetch_text(tranche_url, timeout=600)
        if cache_path:
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            cache_path.write_text(text, encoding="utf-8")

    index: dict[str, dict[str, str]] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("smiles"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        sm, zid = parts[0], parts[1]
        index[sm] = {"zinc_substance_id": zid, "zinc_tranche_url": tranche_url}
        if max_compounds and len(index) >= max_compounds:
            break
    return index


def pubchem_lookup(smiles: str) -> dict[str, Any]:
    body = urllib.parse.urlencode({"smiles": smiles}).encode()
    req = urllib.request.Request(
        "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles/cids/JSON",
        data=body,
        method="POST",
        headers={
            "User-Agent": "BioMate-zinc-lookup/1.0",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode())
    cids = (data.get("IdentifierList") or {}).get("CID") or []
    if not cids:
        return {"pubchem_cids": [], "in_catalog": False}
    cid = int(cids[0])
    prop_url = (
        f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/{cid}"
        f"/property/InChIKey,CanonicalSMILES/JSON"
    )
    req2 = urllib.request.Request(prop_url, headers={"User-Agent": "BioMate-zinc-lookup/1.0"})
    with urllib.request.urlopen(req2, timeout=60) as resp2:
        props = json.loads(resp2.read().decode())
    row = ((props.get("PropertyTable") or {}).get("Properties") or [{}])[0]
    return {
        "pubchem_cids": cids[:5],
        "pubchem_cid_primary": cid,
        "inchikey": row.get("InChIKey"),
        "pubchem_canonical_smiles": row.get("CanonicalSMILES"),
        "in_catalog": True,
    }


def cartblanche_lookup(smiles: str, dist: int = 0) -> list[dict]:
    def parse_tsv(text: str) -> list[dict]:
        text = text.strip()
        if not text or "no valid smiles" in text.lower() or text.lower().startswith("error"):
            return []
        lines = text.splitlines()
        if len(lines) < 2:
            return []
        header = lines[0].split("\t")
        out: list[dict] = []
        for line in lines[1:]:
            parts = line.split("\t")
            if len(parts) < len(header):
                continue
            out.append(dict(zip(header, parts)))
        return out

    def get_url(d: int) -> str:
        enc = urllib.parse.quote(smiles, safe="")
        return (
            f"https://cartblanche22.docking.org/smiles.txt"
            f":smiles={enc}&dist={d}&adist={d}&output_fields=zinc_id,smiles,catalogs,tranche"
        )

    last_err: str | None = None
    for d in (dist, 3 if dist == 0 else dist):
        try:
            req = urllib.request.Request(get_url(d), headers={"User-Agent": "BioMate-zinc-lookup/1.0"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                hits = parse_tsv(resp.read().decode("utf-8", errors="replace"))
            if hits:
                return hits
        except Exception as exc:
            last_err = str(exc)[:200]
    if last_err:
        raise RuntimeError(last_err)
    return []


def lookup_smiles(
    smiles: str,
    *,
    backends: list[str],
    tranche_index: dict[str, dict[str, str]],
) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "smiles": smiles,
        "local_tranche": None,
        "pubchem": None,
        "cartblanche_hits": [],
        "zinc_id": None,
        "in_zinc_tranche": False,
        "in_pubchem": False,
        "in_cartblanche": False,
        "errors": {},
    }

    if "local_tranche" in backends:
        hit = tranche_index.get(smiles)
        if hit:
            entry["local_tranche"] = hit
            entry["zinc_id"] = hit.get("zinc_substance_id") or hit.get("zinc_id")
            entry["in_zinc_tranche"] = True

    if "pubchem" in backends:
        try:
            entry["pubchem"] = pubchem_lookup(smiles)
            entry["in_pubchem"] = bool(entry["pubchem"].get("in_catalog"))
        except Exception as exc:
            entry["errors"]["pubchem"] = str(exc)[:200]

    if "cartblanche" in backends:
        try:
            hits = cartblanche_lookup(smiles)
            entry["cartblanche_hits"] = hits[:5]
            entry["in_cartblanche"] = len(hits) > 0
            if not entry["zinc_id"] and hits:
                entry["zinc_id"] = hits[0].get("zinc_id")
        except Exception as exc:
            entry["errors"]["cartblanche"] = str(exc)[:200]

    entry["in_catalog"] = entry["in_zinc_tranche"] or entry["in_cartblanche"]
    return entry


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument("--top-n", type=int, default=5)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument(
        "--backend",
        action="append",
        choices=("local_tranche", "pubchem", "cartblanche", "all"),
        default=None,
        help="Backends to run (default: local_tranche + pubchem + cartblanche)",
    )
    ap.add_argument("--tranche-url", default=DEFAULT_TRANCHE_URL)
    ap.add_argument("--tranche-max", type=int, default=DEFAULT_LIBRARY_N)
    ap.add_argument("--cache-tranche", type=Path, default=None)
    args = ap.parse_args()

    if args.backend and "all" in args.backend:
        backends = ["local_tranche", "pubchem", "cartblanche"]
    elif args.backend:
        backends = list(dict.fromkeys(args.backend))
    else:
        backends = ["local_tranche", "pubchem", "cartblanche"]

    pub = args.publication_run.resolve()
    assets = pub / "assets"
    tsv_path = assets / "zinc600_library.tsv"
    manifest_path = assets / "zinc600_library.manifest.json"

    tranche_index: dict[str, dict[str, str]] = {}
    if "local_tranche" in backends:
        if tsv_path.is_file():
            with tsv_path.open(newline="", encoding="utf-8") as fh:
                for row in csv.DictReader(fh, delimiter="\t"):
                    sm = (row.get("smiles") or "").strip()
                    zid = (row.get("zinc_substance_id") or "").strip()
                    if sm and zid:
                        tranche_index[sm] = {
                            "zinc_substance_id": zid,
                            "source": "zinc600_library.tsv",
                        }
        else:
            cache = args.cache_tranche or (pub / "zinc600_screen/cache/AAAC_tranche.smi")
            for sm, hit in load_local_tranche_index(
                args.tranche_url, max_compounds=args.tranche_max, cache_path=cache
            ).items():
                tranche_index[sm] = hit

    dock = json.loads(
        (pub / "zinc150_screen/vina/docking_autodock_vina_results.json").read_text(encoding="utf-8")
    )
    ok = [r for r in dock.get("results") or [] if r.get("best_affinity_kcal_mol") is not None]
    top = sorted(ok, key=lambda r: float(r["best_affinity_kcal_mol"]))[: args.top_n]

    rows: list[dict] = []
    for i, hit in enumerate(top, 1):
        sm = hit["smiles"]
        lk = lookup_smiles(sm, backends=backends, tranche_index=tranche_index)
        rows.append(
            {
                "rank": i,
                "vina_kcal_mol": float(hit["best_affinity_kcal_mol"]),
                **lk,
            }
        )

    payload = {
        "looked_up_at": datetime.now(timezone.utc).isoformat(),
        "backends": backends,
        "library_manifest": str(manifest_path) if manifest_path.is_file() else None,
        "library_tsv": str(tsv_path) if tsv_path.is_file() else None,
        "tranche_url": args.tranche_url if "local_tranche" in backends else None,
        "tranche_compounds_indexed": len(tranche_index),
        "top_n": args.top_n,
        "results": rows,
    }
    out = args.out or (pub / "zinc600_screen/ZINC600_TOP5_PURCHASABILITY.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    md_path = out.with_suffix(".md")
    lines = [
        f"# ZINC600 top-{args.top_n} purchasability / identity lookup",
        "",
        f"_Updated: {payload['looked_up_at']}_",
        "",
        f"Backends: **{', '.join(backends)}**",
        "",
        "| Rank | Vina | ZINC ID (tranche) | PubChem CID | In tranche? | CartBlanche | SMILES |",
        "| ---: | ---: | --- | ---: | --- | --- | --- |",
    ]
    for r in rows:
        zid = r.get("zinc_id") or "—"
        pc = "—"
        if r.get("pubchem") and r["pubchem"].get("pubchem_cid_primary"):
            pc = str(r["pubchem"]["pubchem_cid_primary"])
        tr = "yes" if r.get("in_zinc_tranche") else "no"
        cb = "yes" if r.get("in_cartblanche") else ("err" if r.get("errors", {}).get("cartblanche") else "no")
        sm = r["smiles"][:36]
        lines.append(
            f"| {r['rank']} | {r['vina_kcal_mol']:.3f} | {zid} | {pc} | {tr} | {cb} | `{sm}` |"
        )
    lines.extend(
        [
            "",
            "## Notes",
            "",
            "- **local_tranche** matches the publication library source "
            f"([AAAC.smi]({args.tranche_url}), first {args.tranche_max} compounds). "
            "ZINC IDs were stripped when the library was copied; this backend restores them.",
            "- **PubChem** confirms public compound identity; not the same as ZINC vendor catalogs.",
            "- **CartBlanche** is optional; API availability varies by network.",
        ]
    )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out}")
    print(f"Wrote {md_path}")


if __name__ == "__main__":
    main()
