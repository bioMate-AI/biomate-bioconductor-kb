#!/usr/bin/env python3
"""Generate tier_audit.json (RUNS ON EC2): one row per T2 entry (final) with (a) is the source itself a review, (b) was the underlying primary
study opened by workstream K, (c) is the quote the review's own wording or a restatement of a primary result; plus every tier change.
usage: make_tier_audit.py KB.json CONTEXT.json OUT.json"""
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tier_decisions as T

REVIEW_TYPES = ("review-article", "article-commentary")


def main():
    kb, ctx, out = sys.argv[1:4]
    doc = json.load(open(kb)); c = json.load(open(ctx))
    E = {e["id"]: e for e in doc["rules"]}
    rows = []
    chars = dict(T.T2_CHARACTER)
    for rid, (b, a, ch, reason) in T.CHANGES.items():          # entries moved INTO T2 also belong in the table
        if a == "T2":
            chars[rid] = (ch, reason)
    for rid, (ch, reason) in sorted(chars.items()):
        e = E[rid]; x = c.get(rid, {})
        at = x.get("article_type", "")
        own = ch in ("own_analysis",)
        rows.append({
            "id": rid, "kind": e["kind"], "tier_final": e["tier"], "weight_eligible": e["weight_eligible"],
            "source": e["source"]["pmcid"], "source_title": e["source"]["title"], "source_article_type": at,
            "a_source_is_review": at in REVIEW_TYPES,
            "b_underlying_primary_opened": "no" if ch != "own_analysis" else "not_applicable",
            "tier_before": (T.CHANGES[rid][0] if rid in T.CHANGES else "T2"),
            "c_quote_character": ch, "c_explanation": reason,
            "quote": e["quote"], "context_numeric_citation_markers": x.get("numeric_cite_markers_near", []),
        })
    changes = []
    for rid, (b, a, ch, reason) in sorted(T.CHANGES.items()):
        e = E[rid]
        changes.append({"id": rid, "tier_before": b, "tier_after": a, "tier_in_kb": e["tier"], "character": ch, "reason": reason,
                        "source_article_type": c.get(rid, {}).get("article_type", ""), "weight_eligible_after": e["weight_eligible"]})
    t2_ids = sorted(e["id"] for e in doc["rules"] if e["tier"] == "T2")
    res = {"rule": T.__doc__.split("CHANGES =")[0].strip(), "n_entries": len(doc["rules"]),
           "tier_counts": {t: sum(1 for e in doc["rules"] if e["tier"] == t) for t in ("T1", "T2", "T3", "T-internal")},
           "n_weight_eligible": sum(e["weight_eligible"] for e in doc["rules"]),
           "t2_table": rows, "changes": changes,
           "consistency": {"t2_ids_in_kb_equal_table": t2_ids == sorted(r["id"] for r in rows),
                           "all_changes_applied": all(x["tier_in_kb"] == x["tier_after"] for x in changes)},
           "weight_eligibility_effect": "none: eligibility requires tier in {T1,T2} and does not distinguish them",
           "t2_by_character": {}}
    for r in rows:
        res["t2_by_character"][r["c_quote_character"]] = res["t2_by_character"].get(r["c_quote_character"], 0) + 1
    # entries whose T2 is in a review vs not
    res["t2_in_review_sources"] = sum(1 for r in rows if r["a_source_is_review"])
    res["t2_in_primary_sources"] = sum(1 for r in rows if not r["a_source_is_review"])
    json.dump(res, open(out, "w"), indent=1)
    print(json.dumps({k: res[k] for k in ("n_entries", "tier_counts", "n_weight_eligible", "consistency", "t2_by_character", "t2_in_review_sources", "t2_in_primary_sources")}, indent=1))
    assert res["consistency"]["t2_ids_in_kb_equal_table"] and res["consistency"]["all_changes_applied"], res["consistency"]


if __name__ == "__main__":
    main()
