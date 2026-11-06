"""Tests for the knowledge-augmentation module. Run on EC2 (not on the laptop):  CHEMFM_TOK=<tokenizer.json> python -m pytest -x -q knowledge_augment/test_knowledge_augment.py  (from allatom_paper/)."""
import copy
import json
import os
import sys

import numpy as np
import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, AP)
from knowledge_augment import levels as L, ring_potential as RP, prompts as PR  # noqa: E402
from rules.soft import SoftSource, assert_sources_disjoint, forbidden_from_groups  # noqa: E402

TOK = os.environ.get("CHEMFM_TOK", os.path.join(os.environ.get("CHEMFM_DIR", "."), "tokenizer.json"))
needs_tok = pytest.mark.skipif(not os.path.exists(TOK), reason="tokenizer.json not available")


@pytest.fixture(scope="module")
def voc():
    from rules import vocab as V
    return V.load(TOK)


# ------------------------------------------------------------------ levels, determinism, hashes
def test_levels_pure_and_hashed():
    for n in L.LEVELS:
        a, b = L.build_level(n), L.build_level(n)
        assert a.config_hash == b.config_hash and a.soft.weights == b.soft.weights
    assert len({L.build_level(n).config_hash for n in L.LEVELS}) == 4
    assert L.build_level("L2", lam_soft=0.25).config_hash != L.build_level("L2").config_hash
    assert L.build_level("L2", exclude_tokens=("P06756",)).config_hash != L.build_level("L2").config_hash


def test_l0_is_hard_rules_only():
    lv = L.build_level("L0")
    assert lv.lam_soft == 0.0 and lv.ring is None and lv.rule_ids == () and all(v == 0 for v in lv.soft.weights.values())


def test_l1_selection_is_agreed_monotone_only():
    ids, left = L.l1_selection()
    dc = json.load(open(L.P["direction"]))["rules"]
    kb = {e["id"]: e for e in json.load(open(L.P["kb"]))["rules"]}
    assert len(ids) == 14
    for i in ids:
        assert dc[i]["rule_status"] == "agree" and dc[i]["n_agree_cells"] == dc[i]["n_cells"] > 0
        assert kb[i]["weight_eligible"] and kb[i]["quote_verified"] and kb[i]["direction"] in ("+", "-", "multi")
        assert i not in L.EXCLUDED_IDS_EXPLICIT
    assert "LIT-BRO5-001" in left and "window" in left["LIT-BRO5-001"]


def test_l2_adds_ring_only_and_l3_is_group_a_only():
    l1, l2, l3 = L.build_level("L1"), L.build_level("L2"), L.build_level("L3")
    assert l2.soft.weights == l1.soft.weights and l2.ring is not None and l2.ring.weight == 0.5
    assert l3.ring is None and l3.rule_ids == () and "UNVALIDATED" in l3.labels[0]
    assert set(l3.soft.mined_from) == set(L.leak_report()["group_A"])


# ------------------------------------------------------------------ enforced exclusions (size, rotatable bonds, D-residue, non-agreeing)
@pytest.mark.parametrize("level", ["L1", "L2", "L3"])
def test_excluded_entries_receive_zero_potential(level):
    ep = L.entry_potentials(level)
    dc = json.load(open(L.P["direction"]))["rules"]
    kb = {e["id"]: e for e in json.load(open(L.P["kb"]))["rules"]}
    for i, e in kb.items():
        feats = set(e["feat_mapped"])
        excluded = (i in L.EXCLUDED_IDS_EXPLICIT or dc[i]["rule_status"] != "agree" or e.get("direction") == "window" or not e.get("weight_eligible")
                    or (feats and feats <= L.EXCLUDED_FEATURES))
        if excluded:
            p = ep[i]
            assert not p["used"] and p["polar"] == p["carbon"] == p["nme"] == 0.0, (level, i, p)
    for i in ("LIT-SIZE-001", "LIT-SIZE-002", "LIT-STAB-008", "LIT-STAB-002", "LIT-HBD-001", "LIT-BRO5-003", "LIT-NCAA-001"):
        assert kb[i]["weight"] and not ep[i]["used"]            # stored weight is nonzero in the KB file, effective potential is zero


def test_stored_weight_field_is_never_read(tmp_path):
    kb = json.load(open(L.P["kb"]))
    kb2 = copy.deepcopy(kb)
    for e in kb2["rules"]:
        e["weight"] = 7.7
    p = tmp_path / "kb2.json"
    json.dump(kb2, open(p, "w"))
    a = L.literature_agreed_source(kb_path=L.P["kb"])
    b = L.literature_agreed_source(kb_path=str(p))
    assert a.weights == b.weights


def test_size_and_d_residue_cannot_be_forced_in(tmp_path):
    """even if the direction check said 'agree' for the excluded entries, they stay out of every selection."""
    dc = json.load(open(L.P["direction"]))
    for i in L.EXCLUDED_IDS_EXPLICIT:
        dc["rules"][i].update(rule_status="agree", n_agree_cells=2, n_cells=2)
    p = tmp_path / "dc.json"
    json.dump(dc, open(p, "w"))
    ids, left = L.l1_selection(direction_path=str(p))
    assert not set(ids) & L.EXCLUDED_IDS_EXPLICIT
    kb = {e["id"]: e for e in json.load(open(L.P["kb"]))["rules"]}
    src = L.literature_agreed_source(direction_path=str(p))
    ref = L.literature_agreed_source()
    assert src.weights == ref.weights
    # forcing an excluded FEATURE into an otherwise selected entry changes nothing
    kb2 = copy.deepcopy(json.load(open(L.P["kb"])))
    for e in kb2["rules"]:
        if e["id"] == "LIT-HBD-002":
            e["feat_mapped"]["mw"] = -1
            e["feat_mapped"]["n_dres"] = 1
    q = tmp_path / "kb3.json"
    json.dump(kb2, open(q, "w"))
    assert L.literature_agreed_source(kb_path=str(q)).weights == ref.weights


# ------------------------------------------------------------------ leak guard
def test_leak_guard_no_stop_or_heldout_source_in_any_level():
    r = L.leak_report()
    assert r["ok"] and not r["direction_check_overlap_with_S_B"]
    forb = forbidden_from_groups(L.P["groups"])
    assert len(forb) == 18
    for n in L.LEVELS:
        assert not set(L.build_level(n).soft.mined_from) & set(forb)
    bad = SoftSource("x", "x", {"polar": 0, "carbon": 0, "nme": 0}, (forb[0],))
    with pytest.raises(AssertionError):
        assert_sources_disjoint(bad, forb)


# ------------------------------------------------------------------ ring priors: regression and arm-G exclusion
def test_ring_tables_equal_committed_priors():
    rt = RP.ring_tables(())
    ct, cn, sha = RP.committed_tables(L.P["soft_pot"])
    assert rt["targets_sha256"] in sha and len(sha) == 1
    for cls in ct:
        assert rt["n"][cls] == cn[cls]
        for r, v in ct[cls].items():
            assert abs(rt["tables"][cls][r] - v) < 1e-3, (cls, r)


def test_ring_exclusion_removes_targets_and_changes_hash():
    full = RP.ring_tables(())
    tok = open(os.path.join(AP, "structure_knowledge", "results", "exclude_armG_example.txt")).read().split()
    ex = RP.ring_tables(tok)
    assert ex["excluded_targets"] and ex["n_complexes"] < full["n_complexes"] and ex["targets_sha256"] != full["targets_sha256"]
    for k in ex["excluded_targets"]:
        assert k in tok or any(x in tok for x in k.split("+"))
    rows = [r for r in RP._read_lib(RP.LIB_DEFAULT) if not r["receptor_antibody_like"]]
    left = {r["target_key"] for r in rows} - set(ex["excluded_targets"])
    assert RP.hash_targets(left) == ex["targets_sha256"]


def test_excluded_accessions_never_in_prompt_pack():
    tok = open(os.path.join(AP, "structure_knowledge", "results", "exclude_armG_example.txt")).read().split()
    lv = L.build_level("L2", exclude_tokens=tok)
    cards = json.load(open(PR.CARDS))
    for c in cards:
        if set(c.get("receptor_uniprot", [])) & set(tok):
            text, meta = PR.knowledge_block(lv, target=c["target"], exclude_tokens=tok)
            assert "withheld" in text and c["reference_pdb"] not in text
    text, _ = PR.knowledge_block(lv, exclude_tokens=tok, max_tokens=2000)
    ex = RP.ring_tables(tok)
    for k in ex["excluded_targets"]:
        for part in k.split("+"):
            assert part not in text
    assert ex["targets_sha256"] in text


# ------------------------------------------------------------------ prompts
def test_prompt_pack_tiers_ids_budget():
    lv = L.build_level("L1")
    text, meta = PR.knowledge_block(lv, max_tokens=2000)
    assert "[T1]" in text and "[T2]" in text and all(x["id"] in text for x in meta["lines"])
    t_small, m_small = PR.knowledge_block(lv, max_tokens=120)
    assert PR._default_count(t_small) <= 120 and m_small["dropped"] > 0
    assert PR.knowledge_block(L.build_level("L0"))[0] == ""
    assert "UNVALIDATED" in PR.knowledge_block(L.build_level("L3"), max_tokens=2000)[0]
    with pytest.raises(PR.PromptTooLong):
        PR.knowledge_block(lv, max_tokens=5)


def test_control_codes_in_reserved_range():
    for lv in L.LEVELS:
        for r in (4, 7, 10, 13, 20, 30):
            assert all(266 <= i < 320 for i in PR.control_codes(lv, "disulfide", r))
    assert len({PR.control_codes(l)[0] for l in L.LEVELS}) == 4


# ------------------------------------------------------------------ soft potentials shift the sampled distribution (planted rules)
def _prefix_state(con, smiles):
    st = con.init_state(con.vocab.encode(smiles))
    return st


def _q(con, st, voc):
    """next-token distribution for a uniform LM restricted to the feasible set, with the soft potential applied exactly as the sampler does."""
    m = con.mask(st)
    q = np.where(m, 1.0, 0.0)
    if con.lam:
        q = q * np.exp(con.soft_logits(st))
    return q / q.sum()


@needs_tok
def test_planted_polar_weight_shifts_mass_in_intended_direction(voc):
    st_prefix = "N1CC(=O)NCC(=O)"
    ids = [voc.tok2id[t] for t in ("N", "O", "n", "o")]
    mk = lambda w, lam: L.AugmentedConstraint(voc, lam_soft=lam, soft=SoftSource("planted", "planted", {"polar": w, "carbon": 0.0, "nme": 0.0}), ring=None)  # noqa: E731
    q0 = _q(mk(0.0, 0.0), _prefix_state(mk(0.0, 0.0), st_prefix), voc)
    qneg = _q(mk(-2.0, 1.0), _prefix_state(mk(-2.0, 1.0), st_prefix), voc)
    qpos = _q(mk(+2.0, 1.0), _prefix_state(mk(+2.0, 1.0), st_prefix), voc)
    assert qneg[ids].sum() < q0[ids].sum() < qpos[ids].sum()


@needs_tok
def test_zero_weight_changes_nothing(voc):
    from rules.constraint import ChemFMConstraint
    base = ChemFMConstraint(voc)
    st_prefix = "N1CC(=O)NCC(=O)"
    for lam, w in ((0.0, 3.0), (1.0, 0.0)):
        c = L.AugmentedConstraint(voc, lam_soft=lam, soft=SoftSource("p", "p", {"polar": w, "carbon": w, "nme": w}), ring=None)
        st = _prefix_state(c, st_prefix)
        assert np.array_equal(c.mask(st), base.mask(base.init_state(voc.encode(st_prefix))))
        assert np.allclose(c.soft_logits(st), 0.0)
    lv0 = L.build_level("L0")
    c0 = lv0.constraint(voc)
    assert np.allclose(c0.soft_logits(_prefix_state(c0, st_prefix)), 0.0)


def _planted_ring(mode_res, weight):
    t = {r: -6.0 for r in RP.RES_RANGE}
    t[mode_res] = -0.1
    rt = dict(tables={"head_to_tail": t, "amide_like": t, "disulfide": t, "thioether": t}, n={"head_to_tail": 10, "amide_like": 10, "disulfide": 10, "thioether": 10},
              targets_sha256="planted", excluded_sha256=None)
    return RP.RingPotential.build(rt, weight)


@needs_tok
def test_planted_ring_prior_shifts_closure_digit(voc):
    one = voc.tok2id["1"]
    pre = lambda k: "N1" + "CC(=O)N" * (k - 1) + "CC(=O)"   # k residues, closing N1 ... C(=O): amide closure with 3k ring atoms  # noqa: E731
    out = {}
    for k in (5, 8):
        for w in (0.0, 0.5):
            c = L.AugmentedConstraint(voc, lam_soft=1.0, soft=SoftSource.none(), ring=_planted_ring(8, w))
            st = _prefix_state(c, pre(k))
            assert RP.ring_atoms_if_closed(st, "1") == 3 * k
            out[(k, w)] = c.soft_logits(st)[one]
    assert out[(8, 0.5)] == 0.0 and out[(5, 0.5)] < 0.0 and out[(5, 0.0)] == out[(8, 0.0)] == 0.0
    # hard mask identical with and without the potential
    c1 = L.AugmentedConstraint(voc, lam_soft=1.0, soft=SoftSource.none(), ring=_planted_ring(8, 0.5))
    c0 = L.AugmentedConstraint(voc, lam_soft=1.0, soft=SoftSource.none(), ring=None)
    assert np.array_equal(c1.mask(_prefix_state(c1, pre(5))), c0.mask(_prefix_state(c0, pre(5))))


def test_ring_residue_conversion_and_penalty_sign():
    rp = _planted_ring(8, 0.5)
    assert rp.residues("head_to_tail", 24) == 8 and rp.residues("disulfide", 26) == 8
    assert rp.penalty("amide", 24) == 0.0 and rp.penalty("amide", 15) < 0 and rp.penalty("amide", 9) == 0.0   # < min_ring_atoms: no potential
    assert RP.closure_class("S", "s") == "disulfide" and RP.closure_class("c", "S") == "thioether" and RP.closure_class("O", "C") is None
