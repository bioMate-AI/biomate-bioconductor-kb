"""
Bulk-expand the entity_canonicals.yaml by fetching aliases from mygene.info
for a curated seed list of BioMate-relevant genes.

Seed list = ~200 high-traffic genes chosen across:
  - Oncogenes / tumor suppressors  (BRCA1, TP53, KRAS, EGFR, BRAF, ...)
  - Drug targets                   (HER2, ALK, MET, ROS1, ABL1, ...)
  - Rare-disease genes             (CFTR, ARL6IP1, SPAST, DMD, ...)
  - Pharmacology / liver enzymes   (CYP3A4, CYP2D6, UGT1A1, ...)
  - Common immunology / signaling  (TNF, IL6, JAK2, STAT3, ...)

For each seed, calls mygene.info → gets approved name, OMIM ID, all aliases.
Writes a new YAML at sandbox/intent_retrieval_v3/output/entity_canonicals_expanded.yaml
which a future session can merge into backend/config/ after review.

Network-required (uses mygene.info REST). Disk-cached so re-runs are free.
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

OUT_YAML = (
    Path(__file__).resolve().parents[1]
    / "output" / "entity_canonicals_expanded.yaml"
)
CACHE_DIR = ROOT / "sandbox/intent_retrieval_v3/output/.mygene_cache"
CACHE_DIR.mkdir(parents=True, exist_ok=True)


# Curated seed list — ~200 high-traffic BioMate-relevant gene symbols.
# Grouped by domain for readability. Order doesn't matter for output.
SEED_GENES: List[str] = [
    # Oncogenes / tumor suppressors
    "BRCA1", "BRCA2", "TP53", "KRAS", "NRAS", "HRAS", "EGFR", "BRAF", "PIK3CA",
    "PTEN", "APC", "MLH1", "MSH2", "MSH6", "PMS2", "ATM", "CHEK2", "PALB2",
    "MYC", "MYCN", "RB1", "VHL", "NF1", "NF2", "STK11", "CDKN2A", "SMAD4",
    "ARID1A", "ARID2", "KMT2D", "CREBBP", "EP300", "TET2", "DNMT3A", "IDH1",
    "IDH2", "FBXW7", "GNAS", "CTNNB1",

    # Drug targets / receptors / kinases
    "ERBB2", "ERBB3", "ERBB4", "MET", "ALK", "ROS1", "RET", "FGFR1", "FGFR2",
    "FGFR3", "FGFR4", "PDGFRA", "PDGFRB", "VEGFA", "KIT", "ABL1", "BCR",
    "JAK1", "JAK2", "JAK3", "STAT3", "STAT5A", "MTOR", "AKT1", "AKT2", "MEK1",
    "ESR1", "AR", "PGR", "MAPK1", "MAPK3", "ROCK1", "PLK1", "AURKA", "CDK4",
    "CDK6", "CDK9", "PARP1", "BCL2", "MCL1", "XPO1",

    # Rare-disease genes
    "CFTR", "DMD", "HEXA", "HEXB", "ATP7B", "PAH", "GBA", "FXN", "HTT",
    "SOD1", "SCN1A", "SCN2A", "SHANK3", "SETD5", "ARL6IP1", "SPAST", "SPG4",
    "FANCA", "FANCD2", "ABCD1", "MECP2", "UBE3A", "SMN1", "SMN2", "RPS19",
    "RPS17", "ERCC2", "ERCC3", "XPA", "XPC", "BLM", "WRN", "RECQL4",

    # CYP / drug metabolism
    "CYP3A4", "CYP3A5", "CYP2D6", "CYP2C9", "CYP2C19", "CYP1A2", "CYP2B6",
    "CYP2E1", "UGT1A1", "UGT2B7", "SLCO1B1", "ABCB1", "ABCG2", "NAT2",
    "TPMT", "DPYD",

    # Immunology / signaling / inflammation
    "TNF", "IL1B", "IL6", "IL10", "IL17A", "IL23A", "IFNG", "IFNB1", "TGFB1",
    "TGFB2", "NFKB1", "RELA", "FOXP3", "CD4", "CD8A", "CD20", "CD19", "CD22",
    "CD274", "PDCD1", "CTLA4", "LAG3", "TIGIT", "MERTK", "AXL",

    # Hematology / blood
    "HBB", "HBA1", "HBA2", "G6PD", "VWF", "FGA", "FGB", "FGG", "F8", "F9",
    "ABO",

    # Neuro / synaptic
    "APP", "PSEN1", "PSEN2", "APOE", "TREM2", "MAPT", "SNCA", "PRKN", "PINK1",
    "LRRK2", "GRN", "TARDBP", "C9ORF72",

    # Misc high-traffic
    "MTOR", "INS", "INSR", "IGF1", "IGF2", "IGF1R", "LEP", "LEPR",
    "TSHR", "TG", "F5", "F2",
]


def _http_get(url: str, params: dict, timeout: int = 8) -> Optional[dict]:
    """Disk-cached HTTP GET; returns parsed JSON or None."""
    import requests
    cache_key = hashlib.md5(
        f"{url}?{json.dumps(params, sort_keys=True)}".encode()
    ).hexdigest()[:16]
    cache_file = CACHE_DIR / f"{cache_key}.json"
    if cache_file.exists():
        try:
            return json.loads(cache_file.read_text())
        except Exception:
            pass
    try:
        r = requests.get(url, params=params, timeout=timeout,
                          headers={"User-Agent": "BioMate-EntityImport/1.0"})
        if r.status_code != 200:
            return None
        data = r.json()
        try:
            cache_file.write_text(json.dumps(data))
        except Exception:
            pass
        return data
    except Exception as exc:
        logger.debug("HTTP error for %s: %s", url, exc)
        return None


def fetch_gene_info(symbol: str) -> Optional[Dict[str, Any]]:
    """Return {symbol, name, omim_id, aliases:[...]}  or None on failure.

    Calls mygene.info /v3/query?q=<symbol>&fields=symbol,name,alias,MIM,...
    Restricts to human (taxid=9606).
    """
    data = _http_get(
        "https://mygene.info/v3/query",
        {
            "q": f"symbol:{symbol}",
            "fields": "symbol,name,alias,MIM,prev_alias,prev_symbol",
            "species": "human",
            "size": 1,
        },
    )
    if not data or not data.get("hits"):
        return None
    hit = data["hits"][0]
    canonical = hit.get("symbol")
    if not canonical:
        return None
    aliases = set()
    aliases.add(canonical.lower())  # always include canonical itself
    # Common spelling variants of the canonical
    aliases.add(canonical.replace("-", "_").lower())
    aliases.add(canonical.replace("-", " ").lower())
    # alias / prev_symbol / prev_alias from mygene
    for field in ("alias", "prev_alias", "prev_symbol"):
        v = hit.get(field)
        if v is None:
            continue
        if isinstance(v, str):
            aliases.add(v.lower())
        elif isinstance(v, list):
            for a in v:
                if isinstance(a, str):
                    aliases.add(a.lower())
    # Drop very short aliases (< 3 chars) — too noisy
    aliases = {a for a in aliases if len(a) >= 3}
    mim = hit.get("MIM")
    if isinstance(mim, list):
        mim = mim[0] if mim else None
    return {
        "canonical": canonical,
        "name": hit.get("name", canonical),
        "omim_id": str(mim) if mim else "",
        "aliases": sorted(aliases),
    }


def main() -> int:
    print(f"Fetching {len(SEED_GENES)} gene records from mygene.info...")
    records: List[Dict[str, Any]] = []
    failed: List[str] = []
    for i, sym in enumerate(SEED_GENES, 1):
        info = fetch_gene_info(sym)
        if info:
            records.append(info)
        else:
            failed.append(sym)
        if i % 20 == 0:
            print(f"  [{i}/{len(SEED_GENES)}] {len(records)} ok, {len(failed)} failed")
        time.sleep(0.05)  # be nice to mygene.info

    print(f"\nDone: {len(records)} records, {len(failed)} failed")
    if failed:
        print(f"Failed seeds (likely never matched on mygene): {failed[:10]}"
              f"{'…' if len(failed) > 10 else ''}")

    # Write YAML
    OUT_YAML.parent.mkdir(parents=True, exist_ok=True)
    with OUT_YAML.open("w", encoding="utf-8") as f:
        f.write("# Auto-generated entity_canonicals.yaml from mygene.info bulk-import.\n")
        f.write(f"# Source: sandbox/intent_retrieval_v3/scripts/expand_entity_yaml.py\n")
        f.write(f"# Seeds: {len(SEED_GENES)}; succeeded: {len(records)}; failed: {len(failed)}\n")
        f.write("# Date: 2026-05-20\n")
        f.write("# Review before merging into backend/config/entity_canonicals.yaml.\n\n")
        for rec in sorted(records, key=lambda r: r["canonical"]):
            f.write(f"{rec['canonical']}:\n")
            f.write(f"  entity_type: gene\n")
            f.write(f"  aliases:\n")
            for a in rec["aliases"]:
                # quote aliases that contain special chars
                if any(c in a for c in (":", "'", "\"", "#", "&", "{", "}")):
                    f.write(f'    - "{a}"\n')
                else:
                    f.write(f"    - {a}\n")
            f.write(f"  metadata:\n")
            f.write(f'    display_name: "{rec["name"]}"\n')
            if rec["omim_id"]:
                f.write(f'    omim_id: "{rec["omim_id"]}"\n')
            f.write("\n")
    print(f"\nWrote {OUT_YAML.relative_to(ROOT)}")
    print(f"  ({len(records)} genes; {sum(len(r['aliases']) for r in records)} total alias entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
