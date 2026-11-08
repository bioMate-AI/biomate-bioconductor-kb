"""I-B tests (run on EC2): python -m pytest -q test_retrieval.py   (cwd = cyclic_llm, PYTHONPATH includes cyclic_llm/allatom_paper)."""
import hashlib
import os
import sys

import numpy as np
import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
from retrieval import (BlindRule, BlindRuleViolation, EmbeddingIndex, FingerprintIndex, Hit, PromptTooLong, Retriever,
                       RetrievalStore, build_prompt, canon, pharmacophore_text)
from retrieval.index import fp_bits

BASE = "C[C@H]1NC(=O)[C@H](C)NC(=O)[C@H](C)NC1=O"        # cyclo(Ala3) with defined centres
SIB = "C[C@@H]1NC(=O)[C@H](C)NC(=O)[C@H](C)NC1=O"       # stereo sibling (first centre inverted)
VAL = "CC(C)[C@H]1NC(=O)[C@H](C)NC(=O)[C@H](C)NC1=O"
PHE = "C[C@H]1NC(=O)[C@H](Cc2ccccc2)NC(=O)[C@H](C)NC1=O"


def mk(rows):
    st = RetrievalStore()
    for smi, vals, doc, yr, tgt in rows:
        assert st.add(smi, vals, doc, yr, tgt) is not None
    return Retriever(st)


def test_canon_and_flat_key_group_siblings():
    a, b = canon(BASE), canon(SIB)
    assert a[0] != b[0] and a[1] == b[1]


def test_chirality_aware_index_distinguishes_siblings_blind_does_not():
    fa, fb = FingerprintIndex(chiral=True).fit([BASE, SIB]), FingerprintIndex(chiral=False).fit([BASE, SIB])
    assert fb.sims(BASE)[1] == pytest.approx(1.0)
    assert fa.sims(BASE)[1] < 1.0 and fa.sims(BASE)[0] == pytest.approx(1.0)


def test_sibling_is_retrieved_and_ranked_above_a_distant_molecule():
    rt = mk([(SIB, {"pact": 7.0}, "D1", 2015, "t"), (PHE, {"pact": 5.0}, "D2", 2016, "t"), (VAL, {"pact": 6.0}, "D3", 2017, "t")])
    hits = rt.query(BASE, k=3)
    assert [h.smiles for h in hits][0] in (canon(SIB)[0], canon(VAL)[0])
    assert canon(SIB)[0] in [h.smiles for h in hits]
    sib_sim = next(h.sim for h in hits if h.smiles == canon(SIB)[0])
    phe_sim = next(h.sim for h in hits if h.smiles == canon(PHE)[0])
    assert sib_sim > phe_sim


def test_exclude_self_only_removes_exact_isomer_not_siblings():
    rt = mk([(BASE, {"pact": 7}, "D1", 2015, "t"), (SIB, {"pact": 7}, "D2", 2016, "t")])
    assert [h.smiles for h in rt.query(BASE, k=5)] == [canon(SIB)[0]]
    assert len(rt.query(BASE, k=5, exclude_self=False)) == 2
    assert rt.query(BASE, k=5, exclude_flat={canon(BASE)[1]}) == []      # stronger: whole stereo group


def test_exclude_docs_never_returned_and_blind_rule_checks_it():
    rt = mk([(SIB, {"pact": 7}, "HELD", 2020, "t"), (VAL, {"pact": 6}, "OK", 2010, "t"), (PHE, {"pact": 5}, "OK2", 2011, "t")])
    rule = BlindRule.for_answer_docs(["HELD"])
    hits = rt.query(BASE, k=10, **rule.query_kwargs())
    assert hits and all(h.doc != "HELD" for h in hits)
    rule.assert_clean(hits)


def test_control_blind_rule_can_fail():
    """must be able to FAIL: a hit from an excluded document, an answer-set compound, a later year, unknown provenance."""
    rule = BlindRule.for_answer_docs(["HELD"], answer_flat=[canon(SIB)[1]], before_year=2015)
    h = lambda **kw: Hit(**{**dict(smiles="x", sim=1.0, values={}, doc="OK", doc_year=2010, target="t", flat_key="f", source="s"), **kw})
    rule.assert_clean([h()])
    for bad in (h(doc="HELD"), h(flat_key=canon(SIB)[1]), h(doc_year=2016), h(doc=None)):
        with pytest.raises(BlindRuleViolation):
            rule.assert_clean([bad])


def test_strict_mode_excludes_unknown_provenance_under_year_or_doc_rules():
    rt = mk([(SIB, {"pact": 7}, None, None, "t"), (VAL, {"pact": 6}, "OK", 2010, "t")])
    assert len(rt.query(BASE, k=5)) == 2
    assert [h.doc for h in rt.query(BASE, k=5, max_year=2012, strict_docs=True)] == ["OK"]
    assert [h.doc for h in rt.query(BASE, k=5, exclude_docs={"HELD"}, strict_docs=True)] == ["OK"]


def test_year_window():
    rt = mk([(SIB, {"pact": 7}, "A", 2010, "t"), (VAL, {"pact": 6}, "B", 2020, "t")])
    assert [h.doc for h in rt.query(BASE, k=5, max_year=2015)] == ["A"]
    assert [h.doc for h in rt.query(BASE, k=5, min_year=2015)] == ["B"]


def test_determinism_and_tie_break_by_row_index():
    rt = mk([(SIB, {"pact": 1}, "A", 2010, "t"), (SIB, {"pact": 2}, "B", 2011, "t"), (VAL, {"pact": 3}, "C", 2012, "t")])
    r1, r2 = rt.query(BASE, k=3), rt.query(BASE, k=3)
    assert r1 == r2
    assert [h.values["pact"] for h in r1][:2] == [1, 2]            # identical sims -> ascending row index


def test_save_load_roundtrip(tmp_path):
    rt = mk([(SIB, {"pact": 7}, "A", 2010, "t"), (VAL, {"pact": 6}, "B", 2011, "t"), (PHE, {"pact": 5}, "C", 2012, "t")])
    p = str(tmp_path / "ix")
    rt.save(p)
    rt2 = Retriever.load(p)
    assert rt.query(BASE, k=3) == rt2.query(BASE, k=3)
    fp = FingerprintIndex.load(p + ".fp.npz")
    assert np.array_equal(fp.bits, rt.fp.bits)


def test_online_add_is_retrievable():
    rt = mk([(VAL, {"pact": 6}, "B", 2011, "t")])
    assert rt.add(SIB, {"pact": 9.0}, "NEW", 2026, "t") is True
    assert canon(SIB)[0] in [h.smiles for h in rt.query(BASE, k=5)]
    assert rt.add("not a smiles", {"pact": 1}) is False


def test_prompt_budget_drops_farthest_first_and_fixed_part_guard():
    rt = mk([(SIB, {"pact": 7}, "A", 2010, "t"), (VAL, {"pact": 6}, "B", 2011, "t"), (PHE, {"pact": 5}, "C", 2012, "t")])
    hits = rt.query(BASE, k=3)
    full = build_prompt(hits, max_tokens=10_000)
    assert full.used == 3 and full.dropped == 0 and full.text.endswith("New cyclic peptide (SMILES):")
    tight = build_prompt(hits, max_tokens=full.n_tokens_est - 5)
    assert tight.used == 2 and tight.dropped == 1 and tight.n_tokens_est <= full.n_tokens_est - 5
    assert hits[2].smiles not in tight.text and hits[0].smiles in tight.text
    with pytest.raises(PromptTooLong):
        build_prompt(hits, max_tokens=5)


def test_pharmacophore_encoded_flag_is_honest():
    assert "RGD" in (pharmacophore_text("avb6") or "")
    assert pharmacophore_text("no_such_target") is None
    hits = mk([(SIB, {"pact": 7}, "A", 2010, "t")]).query(BASE, k=1)
    assert build_prompt(hits, target="avb6").pharmacophore_encoded is True
    assert build_prompt(hits, target="no_such_target").pharmacophore_encoded is False


def _fake_embed(calls):
    def f(smiles):
        calls.append(len(smiles))
        out = []
        for s in smiles:
            h = hashlib.sha256(s.encode()).digest()
            out.append(np.frombuffer(h, dtype=np.uint8).astype(np.float32)[:16] + 1.0)
        return np.vstack(out)
    return f


def test_embedding_index_cache_alignment_and_hybrid(tmp_path):
    rt = mk([(SIB, {"pact": 7}, "A", 2010, "t"), (VAL, {"pact": 6}, "B", 2011, "t"), (PHE, {"pact": 5}, "C", 2012, "t")])
    calls = []
    smi = [r.smiles for r in rt.store.rows]
    e1 = EmbeddingIndex(cache_dir=str(tmp_path), model_tag="fake").fit(smi, _fake_embed(calls))
    e2 = EmbeddingIndex(cache_dir=str(tmp_path), model_tag="fake").fit(smi, _fake_embed(calls))
    assert calls == [3] and np.array_equal(e1.emb, e2.emb)                    # second fit is a cache hit
    rt.attach_embeddings(e1, _fake_embed(calls))
    assert len(rt.query(BASE, k=3, mode="embedding")) == 3 and len(rt.query(BASE, k=3, mode="hybrid")) == 3
    bad = EmbeddingIndex(model_tag="fake").fit(smi[:2], _fake_embed([]))
    with pytest.raises(AssertionError):
        rt.attach_embeddings(bad, None)


def test_embedding_mode_without_index_raises():
    rt = mk([(SIB, {"pact": 7}, "A", 2010, "t")])
    with pytest.raises(RuntimeError):
        rt.query(BASE, k=1, mode="embedding")
