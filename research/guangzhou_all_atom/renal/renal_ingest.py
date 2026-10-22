"""renal_ingest.py — validate + merge extracted radioligand records into the renal corpus.

Takes JSON/JSONL files of extracted records (from the parallel literature-extraction agents), VALIDATES
each against the corpus invariants, dedupes against what's already in renal_seed_corpus.jsonl, appends the
survivors, and re-runs Gate A. Citation integrity is enforced here: a record with no real source, or no
renal label, or no renal_protection flag, is QUARANTINED (never silently admitted).

Usage:  python3.11 renal_ingest.py <incoming1.json> [incoming2.json ...]
        python3.11 renal_ingest.py --dir /path/to/incoming/   # ingest every *.json / *.jsonl in a dir
"""
from __future__ import annotations
import json, os, sys, glob, re

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "renal_seed_corpus.jsonl")

_LABEL_FIELDS = ("kidney_gy_per_gbq", "tk_ratio", "kidney_pid_g_1h", "kidney_pid_g_2h", "kidney_pid_g_4h", "kidney_pid_g_6h", "kidney_pid_g_24h", "kidney_pid_g_48h")
_PROT_OK = {"none", "lysine_arginine", "succinylated_gelatin", "amino_acid", "gelofusine", "unknown"}
# honest "we don't know" synonyms -> "unknown". NEVER map any of these to "none" (that would impute
# absence of protection, silently corrupting the protected/unprotected stratification).
_PROT_UNKNOWN = {"not_reported", "not reported", "nr", "na", "n/a", "not_applicable",
                 "not_applicable_preclinical", "unspecified", "", None}
_DOI_PMID = re.compile(r"(10\.\d{4,9}/\S+|PMC\d+|PMID[:\s]*\d+|\b\d{7,8}\b)", re.I)


def _norm_protection(r: dict):
    """Normalize the renal_protection flag; honest-unknown synonyms -> 'unknown' (never -> 'none')."""
    v = r.get("renal_protection")
    key = v.strip().lower() if isinstance(v, str) else v
    if key in _PROT_UNKNOWN:
        r["renal_protection"] = "unknown"
    elif isinstance(v, str):
        r["renal_protection"] = v.strip().lower()
    return r


def _has_label(r: dict) -> bool:
    return any(r.get(f) is not None for f in _LABEL_FIELDS)


def validate(r: dict):
    """Return (ok, reason). Enforces: construct_id, real source w/ DOI/PMID, >=1 renal label, protection flag."""
    if not r.get("construct_id"):
        return False, "no construct_id"
    src = str(r.get("source", ""))
    if not src or not _DOI_PMID.search(src):
        return False, f"source lacks a DOI/PMID ('{src[:60]}')"
    if not _has_label(r):
        return False, "no renal label (gy_per_gbq | tk_ratio | kidney_pid_g_*)"
    if "renal_protection" not in r:
        return False, "renal_protection flag MISSING (mandatory — never impute)"
    _norm_protection(r)
    if r["renal_protection"] not in _PROT_OK:
        return False, f"renal_protection '{r['renal_protection']}' not in {sorted(_PROT_OK)}"
    return True, "ok"


def _load_records(paths):
    recs = []
    for p in paths:
        txt = open(p).read().strip()
        # accept a JSON array, or JSONL, or a ```json fenced array pasted from an agent
        m = re.search(r"```(?:json)?\s*(\[.*?\])\s*```", txt, re.S)
        if m:
            txt = m.group(1)
        try:
            obj = json.loads(txt)
            recs.extend(obj if isinstance(obj, list) else [obj])
        except json.JSONDecodeError:
            for line in txt.splitlines():
                line = line.strip().rstrip(",")
                if line.startswith("{"):
                    try:
                        recs.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    return recs


def _doi_key(r: dict):
    m = _DOI_PMID.search(str(r.get("source", "")))
    return m.group(1).lower() if m else ""


def merge(paths, dry_run=False):
    existing = [json.loads(l) for l in open(CORPUS)] if os.path.exists(CORPUS) else []
    # dedup on (construct_id, DOI/PMID): the SAME construct measured in a DIFFERENT study is a distinct,
    # valuable record (inter-study variance), not a duplicate; only same construct + same source is a dup.
    have = {(r["construct_id"], _doi_key(r)) for r in existing}
    incoming = _load_records(paths)

    admitted, quarantined, dupes = [], [], []
    seen_new = set()
    for r in incoming:
        cid = r.get("construct_id")
        key = (cid, _doi_key(r))
        if key in have or key in seen_new:
            dupes.append(cid); continue
        ok, why = validate(r)
        if not ok:
            quarantined.append((cid, why)); continue
        if "verified" not in r:
            r["verified"] = "cited"
        admitted.append(r); seen_new.add(cid)

    if not dry_run and admitted:
        with open(CORPUS, "a") as f:
            for r in admitted:
                f.write(json.dumps(r) + "\n")
    return {"incoming": len(incoming), "admitted": len(admitted), "quarantined": quarantined,
            "dupes": [d for d in dupes if d], "corpus_after": len(existing) + (len(admitted) if not dry_run else 0)}


if __name__ == "__main__":
    args = sys.argv[1:]
    dry = "--dry-run" in args; args = [a for a in args if a != "--dry-run"]
    if args and args[0] == "--dir":
        paths = sorted(glob.glob(os.path.join(args[1], "*.json")) + glob.glob(os.path.join(args[1], "*.jsonl")))
    else:
        paths = args
    if not paths:
        print("usage: renal_ingest.py <file...> | --dir <dir> [--dry-run]"); sys.exit(1)

    res = merge(paths, dry_run=dry)
    print(f"=== renal_ingest ({'DRY RUN' if dry else 'APPLIED'}) ===")
    print(f"  incoming={res['incoming']}  admitted={res['admitted']}  "
          f"quarantined={len(res['quarantined'])}  dupes={len(res['dupes'])}  corpus_after={res['corpus_after']}")
    if res["quarantined"]:
        print("  QUARANTINED (citation-integrity gate):")
        for cid, why in res["quarantined"]:
            print(f"    {cid}: {why}")
    if not dry:
        print("\n--- re-running Gate A ---")
        import importlib, renal_surrogate
        importlib.reload(renal_surrogate)
        r = renal_surrogate.gate_a()
        print(f"  corpus={r['n_corpus']}  with_sequence={r['n_with_sequence']}  with_label={r['n_with_label']}  "
              f"USABLE={r['n_usable_both']} (need >= {r['min_gate_n']})  ->  {r['verdict']}")
        if r["verdict"] not in ("REFUSE_TO_CERTIFY",):
            print(f"  surrogate Spearman={r.get('spearman_surrogate')} vs net-charge baseline={r.get('spearman_net_charge_baseline')}")
