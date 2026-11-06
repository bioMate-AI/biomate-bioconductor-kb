"""Builder for the modality gold set: human targets whose APPROVED drugs (ChEMBL max_phase 4) are predominantly
one modality. Public read-only data: ChEMBL REST (https://www.ebi.ac.uk/chembl/api/data/). Writes
modality_gold.json next to this file. Run:  python -m galaxy.ai.target_id.modality_gold [cache_dir]

Class of a drug (ChEMBL molecule_type): Small molecule -> small_molecule; Antibody, Protein, Enzyme -> biologic;
Oligonucleotide, Oligosaccharide -> other; Cell / Unknown -> ignored. Peptide drugs are typed by ChEMBL as
Protein or Small molecule, so there is NO macrocycle class in the gold (stated limitation).

Target label: >= MIN_DRUGS distinct approved drugs and >= PREDOMINANT share in one class -> that class; otherwise
reported as "mixed" (never forced). Targets with a single approved drug are listed as "single_drug" and excluded
from scoring. 3.9-safe; stdlib only.
"""
import datetime
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from typing import Any, Dict, List, Optional

CHEMBL = "https://www.ebi.ac.uk/chembl/api/data/"
HERE = os.path.dirname(os.path.abspath(__file__))
GOLD_PATH = os.path.join(HERE, "modality_gold.json")
MIN_DRUGS = 2
PREDOMINANT = 0.75
TYPE_CLASS = {"Small molecule": "small_molecule", "Antibody": "biologic", "Protein": "biologic", "Enzyme": "biologic",
              "Oligonucleotide": "other", "Oligosaccharide": "other"}


def _get(url: str, retries: int = 6) -> Any:
    last = None
    for i in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"Accept": "application/json"}), timeout=60) as r:  # nosec
                return json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2 * (i + 1))  # ChEMBL intermittently returns HTTP 500; back off
    raise RuntimeError("ChEMBL request failed after retries: %s (%s)" % (url, last))


def _cached(url: str, cache_dir: Optional[str]) -> Any:
    if not cache_dir:
        return _get(url)
    os.makedirs(cache_dir, exist_ok=True)
    p = os.path.join(cache_dir, "chembl_" + hashlib.sha1(url.encode()).hexdigest() + ".json")
    if os.path.exists(p):
        return json.load(open(p))
    d = _get(url)
    json.dump(d, open(p, "w"))
    time.sleep(0.3)
    return d


def _paged(path: str, key: str, params: Dict[str, str], cache_dir: Optional[str]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    offset = 0
    while True:
        q = dict(params, limit="1000", offset=str(offset))
        d = _cached(CHEMBL + path + ".json?" + urllib.parse.urlencode(q), cache_dir)
        out.extend(d[key])
        if not d["page_meta"]["next"]:
            return out
        offset += 1000


def build(cache_dir: Optional[str]) -> Dict[str, Any]:
    mechs = _paged("mechanism", "mechanisms", {"only": "molecule_chembl_id,target_chembl_id,max_phase"}, cache_dir)
    appr_ids = sorted(set(m["molecule_chembl_id"] for m in mechs if m.get("max_phase") == 4 and m.get("molecule_chembl_id")))
    mol: Dict[str, Dict[str, Any]] = {}
    for i in range(0, len(appr_ids), 50):  # big unfiltered molecule pages return HTTP 500; id batches work
        d = _cached(CHEMBL + "molecule.json?" + urllib.parse.urlencode(
            {"molecule_chembl_id__in": ",".join(appr_ids[i:i + 50]), "limit": "100",
             "only": "molecule_chembl_id,molecule_type,pref_name"}), cache_dir)
        for m in d["molecules"]:
            mol[m["molecule_chembl_id"]] = m
    mols = list(mol.values())
    tgt_drugs: Dict[str, Dict[str, str]] = defaultdict(dict)  # target -> molecule -> class
    for m in mechs:
        mid, tid = m.get("molecule_chembl_id"), m.get("target_chembl_id")
        if not mid or not tid or mid not in mol:
            continue
        cls = TYPE_CLASS.get(mol[mid].get("molecule_type"))
        if cls:
            tgt_drugs[tid][mid] = cls
    tids = sorted(tgt_drugs)
    info: Dict[str, Dict[str, Any]] = {}
    for i in range(0, len(tids), 50):
        d = _cached(CHEMBL + "target.json?" + urllib.parse.urlencode(
            {"target_chembl_id__in": ",".join(tids[i:i + 50]), "limit": "100",
             "only": "target_chembl_id,target_type,pref_name,target_components"}), cache_dir)
        for t in d["targets"]:
            info[t["target_chembl_id"]] = t
    rows, excluded = [], defaultdict(int)
    for tid in tids:
        t = info.get(tid)
        if not t or t.get("target_type") != "SINGLE PROTEIN" or len(t.get("target_components") or []) != 1:
            excluded["not_single_protein"] += 1
            continue
        comp = t["target_components"][0]
        sym = ""
        for s in comp.get("target_component_synonyms") or []:
            if s.get("syn_type") == "GENE_SYMBOL":
                sym = s["component_synonym"]
                break
        counts: Dict[str, int] = defaultdict(int)
        for c in tgt_drugs[tid].values():
            counts[c] += 1
        n = sum(counts.values())
        top = max(counts, key=lambda k: counts[k])
        if n < MIN_DRUGS:
            label = "single_drug"
        elif counts[top] / float(n) >= PREDOMINANT:
            label = top
        else:
            label = "mixed"
        rows.append({"target_chembl_id": tid, "accession": comp.get("accession"), "symbol": sym,
                     "name": t.get("pref_name"), "n_approved_drugs": n, "counts": dict(counts), "label": label,
                     "split": "dev" if int(hashlib.sha1((comp.get("accession") or "").encode()).hexdigest(), 16) % 2 == 0 else "test"})
    return {
        "built": datetime.date.today().isoformat(),
        "sources": [CHEMBL + "mechanism.json (approved-drug mechanisms)",
                    CHEMBL + "molecule.json?molecule_chembl_id__in=... (molecule_type of molecules whose mechanism rows have max_phase=4)",
                    CHEMBL + "target.json (SINGLE PROTEIN targets, UniProt accession)"],
        "rules": {"approved": "ChEMBL max_phase=4", "min_drugs": MIN_DRUGS, "predominant_share": PREDOMINANT,
                  "type_class": TYPE_CLASS, "split": "sha1(accession) parity: even=dev (tuning allowed), odd=test (frozen)"},
        "n_mechanisms": len(mechs), "n_approved_molecules": len(mols), "n_targets_with_drugs": len(tids),
        "excluded": dict(excluded),
        "targets": rows,
    }


if __name__ == "__main__":
    cd = sys.argv[1] if len(sys.argv) > 1 else None
    g = build(cd)
    with open(GOLD_PATH, "w") as f:
        json.dump(g, f, indent=1)
    from collections import Counter
    print(Counter(r["label"] for r in g["targets"]), "->", GOLD_PATH)
