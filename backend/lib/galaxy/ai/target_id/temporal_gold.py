#!/usr/bin/env python3
"""Temporal (post-training-cut-off) approval gold for target identification  (gap T9).

WHY: a language model cannot have memorised a target-disease approval that happened AFTER its training
cut-off. Scoring a channel on only those pairs separates "recalls known targets" from "finds new ones".

WHAT IT BUILDS: pairs (disease id, target gene, drug, first approval, source URL) from ChEMBL:
  molecule (max_phase=4 -> first_approval year, parent molecule)   -> approval year of every approved drug
  mechanism                                                         -> drug -> human protein target(s)
  drug_indication (max_phase_for_ind=4)                             -> drug -> approved indication (EFO/MONDO id)
  target                                                            -> target -> gene symbol
Optional refinements (both free public APIs, cached, off-switchable):
  openFDA drugsfda   -> exact FDA original-approval date for drugs whose ChEMBL year equals the cut-off year
  Open Targets       -> disease-id resolvability, and independent confirmation of drug->(target, indication)

STRICT DEFINITIONS (cut-off C, approval date t; ``pre`` = t < C, ``post`` = t >= C, year-only dates are
``ambiguous`` when the year straddles C):
  NOVEL           the target had NO approved drug in ANY indication that is pre-C, and none whose date is
                  ambiguous/unknown; a post-C drug acting on it is approved for the disease.
  NEW_INDICATION  the target already had a pre-C approved drug (any indication) but the (disease, target)
                  pair had none (no pre-C or ambiguous drug for that exact disease id and target), and a
                  post-C drug acting on the target is approved for the disease.
Anything that cannot be placed cleanly is dropped and counted in ``excluded_summary`` (conservative: it
is better to lose a pair than to put a memorisable one in the "novel" set).

KNOWN LIMITS (also written into every gold file): ChEMBL gives the molecule's first approval anywhere in
the world, year only, not the date of each indication, so a drug first approved earlier but newly approved
for a disease is missed (we under-count new indications, never over-count novel targets); an indication
cannot be dated separately; ChEMBL sometimes lags the regulator by months; indication terms are exact ids
with no ontology roll-up; drug-to-target is the labelled mechanism (multi-target drugs are capped by
``max_targets_per_drug``); the model cut-off dates are vendor statements and are uncertain by months.

3.9-safe, stdlib only.

CLI:  python -m galaxy.ai.target_id.temporal_gold build [--out DIR] [--raw FILE] [--no-fda] [--no-ot]
      python -m galaxy.ai.target_id.temporal_gold rebuild --raw FILE   (offline, from a saved raw dump)
"""
import argparse
import datetime
import gzip
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable, Dict, Iterable, List, Optional, Set, Tuple

BUILDER_VERSION = "1.0"
CHEMBL = "https://www.ebi.ac.uk/chembl/api/data"
OT_GQL = "https://api.platform.opentargets.org/api/v4/graphql"
OPENFDA = "https://api.fda.gov/drug/drugsfda.json"
CHEMBL_CARD = "https://www.ebi.ac.uk/chembl/compound_report_card/%s/"
DEFAULT_CUTOFFS = ["2023-06-30", "2024-06-30", "2025-01-01"]
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "temporal_gold_data")
CACHE_DIR = os.environ.get("TARGETID_TEMPORAL_CACHE", "/tmp/targetid_temporal_cache")

KNOWN_LIMITS = [
    "ChEMBL first_approval is the molecule's first approval ANYWHERE, year resolution only; indications are not dated separately.",
    "A drug approved earlier for disease A and newly approved for disease B is dated at its first approval, so such new indications are missed (under-count); novel targets are never over-counted this way.",
    "ChEMBL can lag regulators by months (approval-date lag); the last months before the query date are incomplete.",
    "Year-only dates in the cut-off year are 'ambiguous'; they are resolved with openFDA ORIG approval dates when available, otherwise dropped.",
    "Disease ids are the exact ChEMBL indication ids converted to OT-style (EFO_/MONDO_/HP_); no ontology roll-up, so a broader pre-cut-off approval of the same target may exist under a parent term (mapping error).",
    "Drug-to-target uses the labelled ChEMBL mechanism; multi-target drugs are capped by max_targets_per_drug; indication-to-mechanism pairing is a cross-product per drug.",
    "Model training cut-offs are vendor statements and uncertain by months; use the cut-off at least 6 months AFTER the stated one when in doubt.",
    "Current Open Targets/literature/known_drug scores were computed AFTER these approvals and leak them; score channels only with leakage-safe evidence (see temporal_eval.LEAKY_DATATYPES).",
]


# ---------------------------------------------------------------------------------------------
# Cut-off logic (pure; unit-tested)
# ---------------------------------------------------------------------------------------------
def parse_date(s: str) -> datetime.date:
    return datetime.date.fromisoformat(s)


def approval_status(year: Optional[int], exact: Optional[str], cutoff: datetime.date) -> str:
    """'pre' (< cutoff) | 'post' (>= cutoff) | 'ambiguous' (year straddles cutoff) | 'unknown'."""
    if exact:
        try:
            d = parse_date(exact)
            return "pre" if d < cutoff else "post"
        except Exception:
            pass
    if not year:
        return "unknown"
    if datetime.date(year, 12, 31) < cutoff:
        return "pre"
    if datetime.date(year, 1, 1) >= cutoff:
        return "post"
    return "ambiguous"


def norm_disease_id(efo: Optional[str]) -> Optional[str]:
    if not efo:
        return None
    return str(efo).strip().replace(":", "_")


def classify(molecules: Dict[str, Dict[str, Any]], mechanisms: List[Dict[str, Any]],
             indications: List[Dict[str, Any]], targets: Dict[str, Dict[str, Any]],
             cutoff: datetime.date, max_targets_per_drug: int = 3) -> Dict[str, Any]:
    """Pure novelty logic over normalised rows (no network).

    molecules  {parent_id: {"name", "year": int|None, "exact": 'YYYY-MM-DD'|None}}   approved drugs only
    mechanisms [{"molecule", "target", "disease_efficacy", "refs": [url], "moa"}]
    indications[{"molecule", "disease_id", "disease_name"}]                           phase-4 indications
    targets    {chembl_target_id: {"type", "organism", "genes": [symbol,...]}}
    Returns {"pairs": [...], "pre_cutoff_approved_targets": [...], "excluded_summary": {...}}.
    """
    status = {m: approval_status(v.get("year"), v.get("exact"), cutoff) for m, v in molecules.items()}

    def human_genes(tid: str) -> List[str]:
        t = targets.get(tid) or {}
        if t.get("organism") not in (None, "Homo sapiens"):
            return []
        return [g.upper() for g in (t.get("genes") or []) if g]

    def is_single(tid: str) -> bool:
        return (targets.get(tid) or {}).get("type") == "SINGLE PROTEIN"

    # drug -> genes (any human protein target, any target type: used for "had an approved drug" checks)
    drug_genes_all: Dict[str, Set[str]] = {}
    drug_genes_gold: Dict[str, Dict[str, Dict[str, Any]]] = {}   # drug -> gene -> mech row (single protein only)
    for mech in mechanisms:
        m = mech.get("molecule")
        if m not in molecules or mech.get("disease_efficacy") == 0:
            continue
        genes = human_genes(mech.get("target"))
        for g in genes:
            drug_genes_all.setdefault(m, set()).add(g)
        if is_single(mech.get("target")):
            for g in genes:
                drug_genes_gold.setdefault(m, {})[g] = mech

    gene_pre: Set[str] = set()
    gene_uncertain: Set[str] = set()      # approved drug with ambiguous/unknown date
    for m, genes in drug_genes_all.items():
        if status[m] == "pre":
            gene_pre |= genes
        elif status[m] in ("ambiguous", "unknown"):
            gene_uncertain |= genes

    drug_inds: Dict[str, List[Dict[str, Any]]] = {}
    for ind in indications:
        if ind.get("molecule") in molecules and ind.get("disease_id"):
            drug_inds.setdefault(ind["molecule"], []).append(ind)

    pair_pre: Set[Tuple[str, str]] = set()
    pair_uncertain: Set[Tuple[str, str]] = set()
    for m, genes in drug_genes_all.items():
        for ind in drug_inds.get(m, []):
            for g in genes:
                if status[m] == "pre":
                    pair_pre.add((ind["disease_id"], g))
                elif status[m] in ("ambiguous", "unknown"):
                    pair_uncertain.add((ind["disease_id"], g))

    excl: Dict[str, int] = {}

    def drop(reason: str) -> None:
        excl[reason] = excl.get(reason, 0) + 1

    pairs: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for m, gmap in drug_genes_gold.items():
        if status[m] != "post":
            continue
        if len(drug_genes_all.get(m, ())) > max_targets_per_drug:
            drop("multi_target_drug_over_cap")
            continue
        for ind in drug_inds.get(m, []):
            d = ind["disease_id"]
            for g, mech in gmap.items():
                if (d, g) in pair_pre:
                    drop("pair_already_approved_pre_cutoff")
                    continue
                if (d, g) in pair_uncertain:
                    drop("pair_has_ambiguous_dated_drug")
                    continue
                if g in gene_pre:
                    subset = "new_indication"
                elif g in gene_uncertain:
                    drop("target_has_ambiguous_dated_approved_drug")
                    continue
                else:
                    subset = "novel"
                mol = molecules[m]
                rec = pairs.get((d, g))
                cand = {
                    "disease_id": d, "disease_name": ind.get("disease_name"), "target_symbol": g,
                    "target_chembl_id": mech.get("target"), "drug_chembl_id": m, "drug_name": mol.get("name"),
                    "first_approval": mol.get("exact") or str(mol.get("year")),
                    "date_precision": "day" if mol.get("exact") else "year",
                    "approval_date_source": mol.get("date_source", "chembl_first_approval"),
                    "approval_source_url": CHEMBL_CARD % m,
                    "mechanism_refs": mech.get("refs") or [], "mechanism_of_action": mech.get("moa"),
                    "subset": subset,
                }
                if rec is None:
                    pairs[(d, g)] = cand
                    cand["other_drugs"] = []
                else:  # keep the earliest drug as primary, list the rest
                    if (cand["first_approval"], m) < (rec["first_approval"], rec["drug_chembl_id"]):
                        cand["other_drugs"] = rec["other_drugs"] + [rec["drug_chembl_id"]]
                        pairs[(d, g)] = cand
                    else:
                        rec["other_drugs"].append(m)
    out = sorted(pairs.values(), key=lambda r: (r["subset"], r["disease_id"], r["target_symbol"]))
    for i, r in enumerate(out):
        r["pair_id"] = "%s|%s" % (r["disease_id"], r["target_symbol"])
    return {"pairs": out, "pre_cutoff_approved_targets": sorted(gene_pre), "excluded_summary": excl,
            "status_counts": {s: sum(1 for v in status.values() if v == s) for s in ("pre", "post", "ambiguous", "unknown")}}


def pre_pairs_by_disease(molecules, mechanisms, indications, targets, cutoff, diseases: Iterable[str]) -> Dict[str, List[str]]:
    """Targets with a pre-cut-off approved drug for each disease id (used to keep known positives out of negatives)."""
    status = {m: approval_status(v.get("year"), v.get("exact"), cutoff) for m, v in molecules.items()}
    want = set(diseases)
    drug_genes: Dict[str, Set[str]] = {}
    for mech in mechanisms:
        t = targets.get(mech.get("target")) or {}
        if mech.get("molecule") in molecules and t.get("organism") in (None, "Homo sapiens"):
            for g in t.get("genes") or []:
                drug_genes.setdefault(mech["molecule"], set()).add(g.upper())
    res: Dict[str, Set[str]] = {}
    for ind in indications:
        m, d = ind.get("molecule"), ind.get("disease_id")
        if d in want and m in molecules and status.get(m) in ("pre", "ambiguous", "unknown"):
            res.setdefault(d, set()).update(drug_genes.get(m, ()))
    return {d: sorted(v) for d, v in res.items()}


# ---------------------------------------------------------------------------------------------
# Network (cached, polite)
# ---------------------------------------------------------------------------------------------
class Fetcher:
    def __init__(self, cache_dir: str = CACHE_DIR, delay: float = 0.4, retries: int = 5, timeout: int = 90):
        self.cache_dir, self.delay, self.retries, self.timeout = cache_dir, delay, retries, timeout
        self.n_requests = 0
        os.makedirs(cache_dir, exist_ok=True)

    def _path(self, key: str) -> str:
        return os.path.join(self.cache_dir, hashlib.sha1(key.encode()).hexdigest() + ".json")

    def get(self, url: str, body: Optional[Dict[str, Any]] = None, allow_404: bool = False) -> Any:
        key = url + (json.dumps(body, sort_keys=True) if body else "")
        p = self._path(key)
        if os.path.exists(p):
            with open(p) as fh:
                return json.load(fh)
        last: Optional[Exception] = None
        for attempt in range(self.retries):
            try:
                time.sleep(self.delay)
                self.n_requests += 1
                req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                             headers={"Content-Type": "application/json", "Accept": "application/json",
                                                      "User-Agent": "biomate-temporal-gold/1.0"})
                data = json.loads(urllib.request.urlopen(req, timeout=self.timeout).read())
                with open(p, "w") as fh:
                    json.dump(data, fh)
                return data
            except urllib.error.HTTPError as e:
                last = e
                if e.code == 404 and allow_404:
                    return None
                time.sleep(2 ** attempt)
            except Exception as e:
                last = e
                time.sleep(2 ** attempt)
        raise RuntimeError("GET failed after %d tries: %s: %s" % (self.retries, url, last))


def chembl_all(f: Fetcher, resource: str, params: Dict[str, Any], key: str, page: int = 200) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    offset = 0
    while True:
        q = dict(params)
        q.update({"limit": page, "offset": offset})
        d = f.get("%s/%s.json?%s" % (CHEMBL, resource, urllib.parse.urlencode(q)))
        rows.extend(d[key])
        nxt = (d.get("page_meta") or {}).get("next")
        if not nxt or not d[key]:
            return rows
        offset += page


def fetch_raw(f: Fetcher) -> Dict[str, Any]:
    """Pull and normalise every ChEMBL table the classifier needs."""
    # The unfiltered molecule listing times out / 500s on the public API (65 s per 20 rows), but filtering by
    # approval year is fast (~11 s per year): one query per year, plus one for approved-but-undated molecules.
    mols_raw: List[Dict[str, Any]] = []
    seen_ids: Set[str] = set()
    year_queries = [{"first_approval__lt": 1960}] + [{"first_approval": y} for y in range(1960, datetime.date.today().year + 1)]
    year_queries.append({"max_phase": 4, "first_approval__isnull": "true"})
    for q in year_queries:
        for m in chembl_all(f, "molecule", q, "molecules", page=100):
            if m["molecule_chembl_id"] not in seen_ids:
                seen_ids.add(m["molecule_chembl_id"])
                mols_raw.append(m)
    molecules: Dict[str, Dict[str, Any]] = {}
    for m in mols_raw:
        cid = m["molecule_chembl_id"]
        parent = (m.get("molecule_hierarchy") or {}).get("parent_chembl_id") or cid
        fa = m.get("first_approval")
        cur = molecules.get(parent)
        yr = int(fa) if fa else None
        if cur is None:
            molecules[parent] = {"name": m.get("pref_name"), "year": yr, "molecule_type": m.get("molecule_type")}
        else:   # salts/forms of one parent: earliest year; keep the parent's own name when present
            if yr and (not cur["year"] or yr < cur["year"]):
                cur["year"] = yr
            if cid == parent and m.get("pref_name"):
                cur["name"] = m["pref_name"]
    mechs_raw = chembl_all(f, "mechanism", {"max_phase": 4}, "mechanisms", page=50)
    mechanisms = []
    for r in mechs_raw:
        mechanisms.append({
            "molecule": r.get("parent_molecule_chembl_id") or r.get("molecule_chembl_id"),
            "target": r.get("target_chembl_id"), "disease_efficacy": r.get("disease_efficacy"),
            "moa": r.get("mechanism_of_action"), "action_type": r.get("action_type"),
            "refs": [x.get("ref_url") for x in (r.get("mechanism_refs") or []) if x.get("ref_url")][:3]})
    inds_raw = chembl_all(f, "drug_indication", {"max_phase_for_ind": 4}, "drug_indications")
    indications = []
    for r in inds_raw:
        indications.append({"molecule": r.get("parent_molecule_chembl_id") or r.get("molecule_chembl_id"),
                            "disease_id": norm_disease_id(r.get("efo_id")), "disease_name": r.get("efo_term") or r.get("mesh_heading")})
    tids = sorted({m["target"] for m in mechanisms if m.get("target")})
    targets: Dict[str, Dict[str, Any]] = {}
    for i in range(0, len(tids), 50):
        chunk = tids[i:i + 50]
        d = f.get("%s/target.json?%s" % (CHEMBL, urllib.parse.urlencode(
            {"target_chembl_id__in": ",".join(chunk), "limit": 100})))
        for t in d["targets"]:
            genes = []
            for c in t.get("target_components") or []:
                syn = [s["component_synonym"] for s in c.get("target_component_synonyms") or [] if s.get("syn_type") == "GENE_SYMBOL"]
                if syn:
                    genes.append(syn[0])
            targets[t["target_chembl_id"]] = {"type": t.get("target_type"), "organism": t.get("organism"), "genes": genes,
                                              "name": t.get("pref_name")}
    return {"query_date": datetime.date.today().isoformat(), "molecules": molecules, "mechanisms": mechanisms,
            "indications": indications, "targets": targets,
            "chembl_total_counts": {"molecules_with_first_approval_or_phase4": len(mols_raw), "mechanisms_phase4": len(mechs_raw),
                                    "indications_phase4": len(inds_raw), "targets": len(targets)}}


# -- optional refinements ------------------------------------------------------------------------
def fda_original_approval(f: Fetcher, name: str, year: int) -> Optional[str]:
    """Earliest FDA ORIG approval date (YYYY-MM-DD) for a drug name, only if its year equals ``year``."""
    if not name:
        return None
    q = urllib.parse.quote('openfda.generic_name:"%s"' % name.lower().replace('"', ""))
    try:
        d = f.get("%s?search=%s&limit=100" % (OPENFDA, q), allow_404=True)
    except Exception:
        return None
    best = None
    for r in (d or {}).get("results", []):
        for s in r.get("submissions") or []:
            if s.get("submission_type") == "ORIG" and s.get("submission_status") == "AP" and s.get("submission_status_date"):
                ds = s["submission_status_date"]
                iso = "%s-%s-%s" % (ds[:4], ds[4:6], ds[6:8])
                if best is None or iso < best:
                    best = iso
    if best and int(best[:4]) == year:
        return best
    return None


def refine_with_fda(f: Fetcher, molecules: Dict[str, Dict[str, Any]], cutoffs: List[datetime.date]) -> int:
    n = 0
    cut_years = {c.year for c in cutoffs}
    for m, v in molecules.items():
        if v.get("year") in cut_years and not v.get("exact") and v.get("name"):
            ex = fda_original_approval(f, v["name"], v["year"])
            if ex:
                v["exact"] = ex
                v["date_source"] = "openFDA drugsfda ORIG approval"
                n += 1
    return n


def ot_check(f: Fetcher, pairs: List[Dict[str, Any]]) -> None:
    """Annotate pairs with Open Targets confirmation: disease id resolves; drug lists the target and an APPROVAL indication."""
    dids = sorted({p["disease_id"] for p in pairs})
    names: Dict[str, str] = {}
    for i in range(0, len(dids), 50):
        q = {"query": "query($ids:[String!]!){diseases(efoIds:$ids){id name}}", "variables": {"ids": dids[i:i + 50]}}
        d = f.get(OT_GQL, body=q)
        for r in ((d.get("data") or {}).get("diseases") or []):
            names[r["id"]] = r["name"]
    drugs = sorted({p["drug_chembl_id"] for p in pairs})
    info: Dict[str, Dict[str, Any]] = {}
    for i in range(0, len(drugs), 25):
        q = {"query": "query($ids:[String!]!){drugs(chemblIds:$ids){id mechanismsOfAction{rows{targets{approvedSymbol}}} "
                      "indications{rows{disease{id} maxClinicalStage}}}}", "variables": {"ids": drugs[i:i + 25]}}
        d = f.get(OT_GQL, body=q)
        for r in ((d.get("data") or {}).get("drugs") or []):
            tg = {t["approvedSymbol"].upper() for row in r["mechanismsOfAction"]["rows"] for t in row["targets"]}
            ap = {x["disease"]["id"] for x in r["indications"]["rows"] if x.get("maxClinicalStage") == "APPROVAL"}
            info[r["id"]] = {"targets": tg, "approved_diseases": ap}
    for p in pairs:
        i = info.get(p["drug_chembl_id"])
        p["ot_disease_resolves"] = p["disease_id"] in names
        p["ot_disease_name"] = names.get(p["disease_id"])
        p["ot_confirms_target"] = bool(i and p["target_symbol"] in i["targets"])
        p["ot_confirms_indication"] = bool(i and p["disease_id"] in i["approved_diseases"])


# ---------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------
def build_gold(raw: Dict[str, Any], cutoff_s: str, max_targets_per_drug: int = 3, out_dir: Optional[str] = None,
               fetcher: Optional[Fetcher] = None, ot: bool = True) -> Dict[str, Any]:
    cutoff = parse_date(cutoff_s)
    res = classify(raw["molecules"], raw["mechanisms"], raw["indications"], raw["targets"], cutoff, max_targets_per_drug)
    pairs = res["pairs"]
    if ot and fetcher is not None and pairs:
        try:
            ot_check(fetcher, pairs)
        except Exception as e:
            res["excluded_summary"]["ot_check_failed"] = 1
            sys.stderr.write("OT check failed: %s\n" % e)
    diseases = sorted({p["disease_id"] for p in pairs})
    counts: Dict[str, Any] = {"total": len(pairs)}
    for sub in ("novel", "new_indication"):
        sp = [p for p in pairs if p["subset"] == sub]
        counts[sub] = {"pairs": len(sp), "distinct_targets": len({p["target_symbol"] for p in sp}),
                       "diseases": len({p["disease_id"] for p in sp}),
                       "diseases_with_ge2_pairs": sum(1 for d in {p["disease_id"] for p in sp}
                                                      if sum(1 for p in sp if p["disease_id"] == d) >= 2),
                       "ot_disease_resolves": sum(1 for p in sp if p.get("ot_disease_resolves")),
                       "ot_confirms_target": sum(1 for p in sp if p.get("ot_confirms_target")),
                       "ot_confirms_indication": sum(1 for p in sp if p.get("ot_confirms_indication")),
                       "date_precision_day": sum(1 for p in sp if p["date_precision"] == "day")}
    gold = {
        "meta": {
            "builder": "galaxy.ai.target_id.temporal_gold", "builder_version": BUILDER_VERSION,
            "cutoff": cutoff_s, "cutoff_semantics": "pre = approval date < cutoff; post (gold) = date >= cutoff; year-only in cutoff year = ambiguous (dropped)",
            "query_date": raw.get("query_date"), "max_targets_per_drug": max_targets_per_drug,
            "sources": {"chembl_api": CHEMBL, "endpoints": ["molecule?max_phase=4", "mechanism?max_phase=4",
                                                            "drug_indication?max_phase_for_ind=4", "target"],
                        "openfda": OPENFDA + " (refines cut-off-year dates)", "open_targets": OT_GQL + " (disease resolve + drug cross-check)"},
            "chembl_totals": raw.get("chembl_total_counts"), "molecule_status_counts": res["status_counts"],
            "counts": counts, "excluded_summary": res["excluded_summary"], "known_limits": KNOWN_LIMITS,
        },
        "pairs": pairs,
        "pre_cutoff_approved_targets_global": res["pre_cutoff_approved_targets"],
        "pre_cutoff_approved_targets_by_disease": pre_pairs_by_disease(
            raw["molecules"], raw["mechanisms"], raw["indications"], raw["targets"], cutoff, diseases),
    }
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, "temporal_gold_%s.json" % cutoff_s), "w") as fh:
            json.dump(gold, fh, indent=1, sort_keys=True)
    return gold


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("cmd", choices=["build", "rebuild"])
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--raw", default=None, help="saved raw dump (json.gz) to rebuild from")
    ap.add_argument("--cutoffs", nargs="*", default=DEFAULT_CUTOFFS)
    ap.add_argument("--no-fda", action="store_true")
    ap.add_argument("--no-ot", action="store_true")
    ap.add_argument("--max-targets-per-drug", type=int, default=3)
    a = ap.parse_args(argv)
    f = Fetcher()
    raw_path = a.raw or os.path.join(a.out, "chembl_raw.json.gz")
    if a.cmd == "build":
        raw = fetch_raw(f)
        if not a.no_fda:
            n = refine_with_fda(f, raw["molecules"], [parse_date(c) for c in a.cutoffs])
            print("openFDA exact dates resolved: %d" % n)
            raw["fda_refined"] = n
        os.makedirs(a.out, exist_ok=True)
        with gzip.open(raw_path, "wt") as fh:
            json.dump(raw, fh)
    else:
        with gzip.open(raw_path, "rt") as fh:
            raw = json.load(fh)
    for c in a.cutoffs:
        g = build_gold(raw, c, a.max_targets_per_drug, a.out, fetcher=None if a.no_ot else f, ot=not a.no_ot)
        print(c, json.dumps(g["meta"]["counts"]))
    print("HTTP requests this run: %d (cache %s)" % (f.n_requests, f.cache_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main())
