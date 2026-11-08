"""Build the retrieval stores from the existing assets and report coverage (EC2/Spark only). Writes stats JSON and saved indices.
  store_G  : long_all.csv.gz (8 integrin targets; document ids + years exist) -> the arm-G store
  store_P  : pair_labels + compounds (793 targets, exact potencies; NO document ids) -> context store for non-blind arms only"""
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
from retrieval import Retriever, RetrievalStore  # noqa: E402

GA = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def stats(st):
    n = len(st.rows)
    yrs = [r.doc_year for r in st.rows if r.doc_year is not None]
    return dict(n_rows=n, n_unique_smiles=len({r.smiles for r in st.rows}), n_unique_flat=len({r.flat_key for r in st.rows}),
                n_targets=len({r.target for r in st.rows}), n_docs=len({r.doc for r in st.rows if r.doc}),
                frac_with_doc=round(sum(r.doc is not None for r in st.rows) / max(n, 1), 4),
                year_min=min(yrs) if yrs else None, year_max=max(yrs) if yrs else None,
                top_targets=Counter(r.target for r in st.rows).most_common(5))


def main(out):
    os.makedirs(out, exist_ok=True)
    res = {}
    g = RetrievalStore.from_long_all(os.path.join(GA, "multitarget", "integrin_chembl", "data", "long_all.csv.gz"))
    res["store_G_long_all"] = stats(g)
    Retriever(g).save(os.path.join(out, "store_G"))
    p = RetrievalStore.from_pair_labels(os.path.join(GA, "multitarget", "integrin_chembl", "retro_recovery", "data", "pair_labels.csv.gz"),
                                        os.path.join(GA, "multitarget", "integrin_chembl", "retro_recovery", "data", "compounds.csv.gz"))
    res["store_P_pair_labels"] = stats(p)
    # blind-rule behaviour on the real arm-G store: hold out the newest document of the best-covered target
    rt = Retriever(g)
    tg = Counter(r.target for r in g.rows).most_common(1)[0][0]
    docs = Counter((r.doc, r.doc_year) for r in g.rows if r.target == tg and r.doc)
    held_doc, held_year = max(docs, key=lambda k: (k[1] or 0, docs[k]))
    held_rows = [r for r in g.rows if r.doc == held_doc and r.target == tg]
    from retrieval import BlindRule
    rule = BlindRule.for_answer_docs([held_doc], [r.flat_key for r in held_rows], before_year=held_year)
    leaks = 0
    for r in held_rows[:50]:
        hits = rt.query(r.smiles, k=8, **rule.query_kwargs())
        rule.assert_clean(hits)
        leaks += sum(1 for h in hits if h.doc == held_doc)
    res["blind_rule_real_store"] = dict(target=tg, held_doc=held_doc, held_year=held_year, n_answer_rows=len(held_rows),
                                        queries=min(50, len(held_rows)), excluded_doc_hits=leaks)
    json.dump(res, open(os.path.join(out, "store_stats.json"), "w"), indent=1, default=str)
    print(json.dumps(res, indent=1, default=str))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/w/out")
