#!/usr/bin/env python3
"""Build knowledge_kb_v1.json from the raw rule batches, verifying every quote verbatim against the stored Europe PMC full text.
RUNS ON EC2.  usage: build_kb.py FETCH_DIR OUT_DIR [ACCESS_DATE]
FETCH_DIR holds index.json + fulltext/<PMCID>.txt written by fetch_fulltext.py (normalised text, same norm() as here).
"""
import hashlib, json, os, sys, importlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_fulltext import norm
from kb_schema import SCHEMA_VERSION, COMPUTABLE, PROXY, validate, quote_words, outcome_class

BATCHES = ["rules_raw_batch1", "rules_raw_batch2", "rules_raw_batch3", "rules_raw_batch4", "rules_raw_batch5", "rules_raw_batch6"]
CONF_SCALE = {"high": 1.0, "medium": 0.5, "low": 0.0}
BASE_W = 0.10


def load_raw():
    seen = None
    for b in BATCHES:
        m = importlib.import_module(b)
        seen = m.R
    return list(seen)


def load_fetch(dirs):
    """dirs: comma-separated fetch directories; returns (merged index, text finder)."""
    dl = [d for d in dirs.split(",") if d]
    index = {}
    for d in dl:
        index.update(json.load(open(os.path.join(d, "index.json"))))

    def text_of(key):
        for d in dl:
            fp = os.path.join(d, "fulltext", key.replace(":", "_") + ".txt")
            if os.path.exists(fp):
                return open(fp).read()
        return ""
    return index, text_of


def main():
    fetch, out = sys.argv[1], sys.argv[2]
    access = sys.argv[3] if len(sys.argv) > 3 else "2026-10-29"
    os.makedirs(out, exist_ok=True)
    index, text_of = load_fetch(fetch)
    raw = load_raw()
    ids = [r["id"] for r in raw]
    assert len(ids) == len(set(ids)), "duplicate rule ids"
    texts, kb, problems = {}, [], {}
    for r in raw:
        internal = bool(r.get("path"))
        pm = r.get("pmcid") or ("path:" + r["path"])
        meta = {} if internal else index.get(pm, {})
        if pm not in texts:
            bn = os.path.basename(r["path"]) if internal else ""
            texts[pm] = (norm(open(bn).read()) if os.path.exists(bn) else "") if internal else text_of(pm)
        full = texts[pm]
        q = norm(r["quote"])
        off = full.find(q) if full else -1
        extra = [norm(x) for x in r.get("quotes", [])]
        extra_ok = [bool(full) and (full.find(x) >= 0) for x in extra]
        verified = off >= 0 and all(extra_ok)
        feat = r.get("feat")
        kind = r.get("kind", "rule")
        direction = r["direction"]
        mapped = {}
        if feat:
            for f, sgn in feat.items():
                if f in COMPUTABLE:
                    mapped[f] = sgn
                elif f in PROXY:
                    mapped[PROXY[f]] = (sgn, "proxy")
        eligible = bool(verified and r["tier"] in ("T1", "T2") and kind in ("rule", "fundamental") and direction in ("+", "-", "multi", "window")
                        and mapped and CONF_SCALE[r["confidence"]] > 0
                        and not (direction == "window" and "window" not in r))
        weight = round(BASE_W * CONF_SCALE[r["confidence"]], 4) if eligible else 0.0
        e = {
            "id": r["id"], "kind": kind, "statement": r["statement"], "direction": direction,
            "feat": feat, "feat_mapped": {k: (v if isinstance(v, int) else v[0]) for k, v in mapped.items()},
            "feat_proxy": [k for k, v in mapped.items() if not isinstance(v, int)],
            "window": r.get("window"), "scope": r["scope"], "outcome": r["outcome"], "outcome_class": outcome_class(r["outcome"]), "effect": r.get("effect"),
            "applicable_target": r.get("applicable_target"), "structure_ref": r.get("structure_ref"),
            "tier": r["tier"],
            "source": ({"pmcid": "", "doi": "", "url": "", "path": r["path"], "title": r.get("title", ""), "date": r.get("date", ""), "type": "internal",
                        "text_sha256": hashlib.sha256(full.encode()).hexdigest() if full else ""} if internal else
                       {"pmcid": pm, "doi": meta.get("doi", ""), "title": meta.get("title", ""), "journal": meta.get("journal", ""),
                       "year": meta.get("year", ""), "license": meta.get("license", "")[:160],
                       "type": "preprint" if pm.startswith("arXiv:") else "article",
                       "url": (f"https://arxiv.org/abs/{pm[6:]}" if pm.startswith("arXiv:") else f"https://europepmc.org/article/PMC/{pm}"),
                       "text_sha256": hashlib.sha256(full.encode()).hexdigest() if full else ""}),
            "quote": r["quote"], "quotes": r.get("quotes", []), "card": r.get("card"),
            "quote_words": quote_words(r["quote"]), "quote_verified": verified, "quote_offset": off,
            "access_date": access, "extracted_by": "workstream K (Claude); quote verified verbatim against Europe PMC OA full text by build_kb.py",
            "confidence": r["confidence"], "notes": r.get("notes", ""),
            "weight_eligible": eligible, "weight": weight, "proxy_scale": 0.5,
            "status": "ok" if verified else "UNVERIFIED_QUOTE",
        }
        pr = validate(e)
        if pr:
            problems[e["id"]] = pr
        kb.append(e)
    kb.sort(key=lambda x: x["id"])
    counts = {"n": len(kb), "by_tier": {}, "by_kind": {}, "verified": sum(1 for e in kb if e["quote_verified"]),
              "weight_eligible": sum(1 for e in kb if e["weight_eligible"]),
              "sources": sorted({e["source"]["pmcid"] or e["source"]["path"] for e in kb})}
    for e in kb:
        counts["by_tier"][e["tier"]] = counts["by_tier"].get(e["tier"], 0) + 1
        counts["by_kind"][e["kind"]] = counts["by_kind"].get(e["kind"], 0) + 1
    doc = {"schema_version": SCHEMA_VERSION, "access_date": access, "counts": counts, "problems": problems, "rules": kb}
    blob = json.dumps(doc, indent=1, sort_keys=True)
    open(os.path.join(out, "knowledge_kb_v1.json"), "w").write(blob)
    sha = hashlib.sha256(blob.encode()).hexdigest()
    open(os.path.join(out, "knowledge_kb_v1.sha256"), "w").write(sha + "  knowledge_kb_v1.json\n")
    print(json.dumps(counts, indent=1)); print("problems:", problems); print("sha256", sha)
    bad = [e["id"] for e in kb if not e["quote_verified"]]
    print("UNVERIFIED QUOTES:", bad)


if __name__ == "__main__":
    main()
