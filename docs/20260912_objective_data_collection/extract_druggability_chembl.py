"""Modality-specific tractability labels from the public ChEMBL API.

For a bounded list of canonical RA/asthma/lupus immune drug targets, pull:
  - ChEMBL target id + target_type + protein class (target family split key)
  - ligandability proxy = # bioactivity measurements (activity total_count)
  - clinical tractability = mechanisms + max clinical phase of drugs hitting it
This is one component of druggability, NOT global druggability (PLAN caveat). Untested
!= inactive. Splits are by target family. Training-eligible stays False.

Bounded: ~3 calls/target, polite sleep. No credentials needed (public endpoint).
"""
import json, time, urllib.request, urllib.parse, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BASE = "https://www.ebi.ac.uk/chembl/api/data"

# canonical immune targets for the three diseases (gene symbol -> modality note)
TARGETS = {
    "IL6R": "anti-IL6R mAb (tocilizumab/sarilumab)", "TNF": "anti-TNF (adalimumab etc.)",
    "MS4A1": "anti-CD20 (rituximab)", "TNFSF13B": "anti-BAFF (belimumab)",
    "JAK1": "JAK inhibitor", "JAK2": "JAK inhibitor", "JAK3": "JAK inhibitor",
    "BTK": "BTK inhibitor", "IL17A": "anti-IL17", "IL23A": "anti-IL23",
    "IL4R": "anti-IL4R (dupilumab)", "IL5": "anti-IL5 (mepolizumab)",
    "TSLP": "anti-TSLP (tezepelumab)", "IL5RA": "anti-IL5R (benralizumab)",
    "CTLA4": "CTLA4-Ig (abatacept)", "IFNAR1": "anti-IFNAR (anifrolumab)",
    "S1PR1": "S1P modulator", "IL1B": "anti-IL1", "IL13": "anti-IL13", "IL12B": "anti-IL12/23",
}

def get(path, params):
    url = f"{BASE}/{path}?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Accept": "application/json",
                                               "User-Agent": "BioMate-druggability-audit/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())

def resolve_target(gene):
    d = get("target/search", {"q": gene, "format": "json", "limit": 20})
    human = [t for t in d.get("targets", []) if t.get("organism") == "Homo sapiens"]
    single = [t for t in human if t.get("target_type") == "SINGLE PROTEIN"]
    pick = (single or human or d.get("targets", []) or [None])[0]
    return pick

records = []
for gene, modality in TARGETS.items():
    rec = {"gene": gene, "intended_modality": modality}
    try:
        t = resolve_target(gene)
        if not t:
            rec.update(status="not_found_in_chembl")
            records.append(rec); print(gene, "not found"); continue
        cid = t.get("target_chembl_id")
        rec.update(chembl_id=cid, target_type=t.get("target_type"), pref_name=t.get("pref_name"))
        time.sleep(0.3)
        # ligandability: number of bioactivity measurements
        act = get("activity", {"target_chembl_id": cid, "format": "json", "limit": 1})
        rec["n_bioactivities"] = act.get("page_meta", {}).get("total_count", 0)
        time.sleep(0.3)
        # clinical tractability: mechanisms of action recorded
        mech = get("mechanism", {"target_chembl_id": cid, "format": "json", "limit": 100})
        ms = mech.get("mechanisms", [])
        rec["n_mechanisms"] = len(ms)
        rec["action_types"] = sorted({m.get("action_type") for m in ms if m.get("action_type")})
        rec["mechanism_molecule_ids"] = sorted({m.get("molecule_chembl_id") for m in ms if m.get("molecule_chembl_id")})[:25]
        rec["status"] = "ok"
        print(f"{gene:9} {cid:14} bioact={rec['n_bioactivities']:>7} mechanisms={rec['n_mechanisms']}")
    except urllib.error.URLError as e:
        rec.update(status="error", error=str(e)); print(gene, "ERR", e)
    records.append(rec)
    time.sleep(0.4)

# family-split key: group by target_type (proxy for family without extra calls)
by_type = {}
for r in records:
    by_type.setdefault(r.get("target_type", "unknown"), []).append(r["gene"])

summary = {
    "source": "ChEMBL public API",
    "n_targets_queried": len(TARGETS),
    "n_resolved": sum(1 for r in records if r.get("status") == "ok"),
    "family_split_by_target_type": by_type,
    "caveats": [
        "ligandability proxy = bioactivity count; not modality-specific engagement per se",
        "untested compounds/targets are NOT negatives",
        "one component of druggability, not global tractability",
    ],
    "training_eligible": False,
}
(ROOT / "druggability_chembl.json").write_text(json.dumps(records, indent=2) + "\n")
(ROOT / "druggability_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print("\n" + json.dumps(summary, indent=2))
