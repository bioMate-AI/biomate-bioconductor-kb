#!/usr/bin/env python3
"""Evidence extraction for the tier audit (RUNS ON EC2). For every KB entry: source article-type (from the stored Europe PMC XML:
article-type attribute and presence of Methods/Results sections), and the quote's context (2 sentences before/after in the stored full text),
plus whether the quote or its sentence carries a numeric citation marker. usage: tier_audit_context.py KB.json FETCH_DIRS OUT.json"""
import json, os, re, sys
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_fulltext import norm
from build_kb import load_fetch


def article_type(fetch_dirs, pmcid):
    if pmcid.startswith("arXiv:"):
        return {"article_type": "preprint", "has_methods": True, "has_results": True}
    for d in fetch_dirs:
        fp = os.path.join(d, "raw", pmcid + ".xml")
        if os.path.exists(fp):
            root = ET.parse(fp).getroot()
            art = root if root.tag == "article" else root.find(".//article")
            titles = [(s.findtext("title") or "").strip().lower() for s in art.iter("sec")]
            return {"article_type": art.get("article-type", ""), "has_methods": any("method" in t for t in titles),
                    "has_results": any("result" in t for t in titles), "n_sections": len(titles)}
    return {"article_type": "", "has_methods": None, "has_results": None}


def main():
    kb, fetch, out = sys.argv[1:4]
    doc = json.load(open(kb))
    dirs = [d for d in fetch.split(",") if d]
    _, text_of = load_fetch(fetch)
    res = {}
    for e in doc["rules"]:
        s = e["source"]
        key = s["pmcid"] or s["path"]
        if e["tier"] == "T-internal":
            res[e["id"]] = {"internal": True}
            continue
        full = text_of(s["pmcid"])
        q = norm(e["quote"])
        i = full.find(q)
        ctx = {}
        if i >= 0:
            # sentence-ish windows
            left = full[max(0, i - 420): i]
            right = full[i + len(q): i + len(q) + 420]
            ctx = {"before": left, "quote_in_text": full[i:i + len(q)], "after": right}
            window = full[max(0, i - 60): i + len(q) + 90]
            ctx["numeric_cite_markers_near"] = re.findall(r"(?<=[a-z\)\.])\d{1,3}(?:[,–\-]\d{1,3})*(?=[\s\.,;]|$)", window)[:8]
            ctx["cue_words"] = [w for w in ("previously", "reported", "has been", "have been", "et al", "studies show", "ref", "according to", "we ", "our ", "here we", "were observed", "we observed", "we found", "(Figure", "(Fig", "Table") if w.lower() in (left[-260:] + q + right[:160]).lower()]
        res[e["id"]] = {"pmcid": s["pmcid"], "title": s["title"], "journal": s["journal"], **article_type(dirs, s["pmcid"]), **ctx}
    json.dump(res, open(out, "w"), indent=1)
    print(len(res), "entries")


if __name__ == "__main__":
    main()
