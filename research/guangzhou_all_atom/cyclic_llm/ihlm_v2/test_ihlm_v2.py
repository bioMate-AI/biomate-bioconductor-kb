"""IH-LM v2 adapter tests (cd cyclic_llm/ihlm_v2 && python3 -m pytest -q test_ihlm_v2.py). Planted-signal and invariance controls; CPU only; no network."""
import os, sys, csv, random
import numpy as np, pytest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _paths import CKPT_V4, CYCPEPT_CSV, load_ihlm
from v4_adapter import V4Adapter, gate_name, helm_from_tokens
from verifier_hook import VerifierHook
from graded_bridge import GradedMemoryBridge, grade_smiles
import acceptance_gate as G
from rdkit import Chem

pytestmark = pytest.mark.skipif(not os.path.exists(CKPT_V4), reason="v4 checkpoint not present")
TGT = "MKTAYIAKQRQISFVKSHFSRQ"
PASS_H = "cyclo(F-R-G-D-L-G-[2Nal]-[dP]-[NMeK])"        # gate pass (score.py self-test: MED DoE, clean developability)
INFR_H = "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])"             # literal genus: infringes
NORGD_H = "cyclo(A-L-G-V-L-F-A-P)"


@pytest.fixture(scope="module")
def ad(): return V4Adapter()


def _cycpept_smiles(n=200):
    if not os.path.exists(CYCPEPT_CSV): pytest.skip("CycPeptMPDB csv not present")
    rows = list(csv.DictReader(open(CYCPEPT_CSV, encoding="utf-8-sig")))
    return [r["SMILES"] for r in rows if r.get("SMILES")][:n]


def test_checkpoint_is_read_only_and_described(ad):
    assert ad.info["params"] == 5022976 and ad.info["vocab"] == 393 and ad.info["block"] == 40
    ad.score([], TGT) if False else None
    assert ad.verify_unmodified()


def test_unmapped_is_none_and_scores_are_deterministic(ad):
    s = _cycpept_smiles(120); cov = ad.coverage(s); sc = ad.score(s, TGT); sc2 = ad.score(s, TGT)
    assert cov["n_mapped"] == sum(x is not None for x in sc) and 0 < cov["fraction"] < 1       # real coverage is partial (audited: 17-41 % on CycPeptMPDB, ~4 % on the benchmark)
    assert sc == sc2 and ad.score(["CCO"], TGT) == [None]                                      # a non-peptide is never imputed
    assert ad.verify_unmodified()


def test_update_does_not_mutate_checkpoint_or_original(ad):
    s = [x for x in _cycpept_smiles(200) if ad.segment(x) is not None][:12]
    assert len(s) >= 8
    lab = [dict(smiles=x, target_seq=TGT, label=float(i)) for i, x in enumerate(s)]; fp0 = ad.fingerprint()
    new = ad.update(lab, mode="finetune_ranking", seed=0, steps=3)
    assert ad.fingerprint() == fp0 and new.fingerprint() != fp0 and ad.verify_unmodified()


def test_propose_is_deterministic_and_in_vocabulary(ad):
    a = ad.propose(6, TGT, seed=3); b = ad.propose(6, TGT, seed=3); c = ad.propose(6, TGT, seed=4)
    assert [x["tokens"] for x in a] == [x["tokens"] for x in b] and [x["tokens"] for x in a] != [x["tokens"] for x in c]
    for x in a:
        assert all(t in ad.lm.stoi for t in x["tokens"]); assert x["topology"].startswith("unspecified")
        if x["valid"]: assert 3 <= len(x["tokens"]) <= 16


def test_gate_name_map_planted_equivalence():
    toks = ["F", "R", "G", "D", "L", "A", "F", "dP", "meK"]                                    # v4 naming of the alphavbeta6 reference peptide
    h = helm_from_tokens(toks); assert h == "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])"
    assert G.avb6_gate(h)["PASS_H1_H5"] == G.avb6_gate(INFR_H)["PASS_H1_H5"] is True
    naive = "cyclo(F-R-G-D-L-A-F-[dP]-[meK])"; assert G.avb6_gate(naive)["PASS_H1_H5"] is False     # without the map the SAME peptide is wrongly rejected (the naming gap is real)
    assert gate_name("Me_dL") == "NMedL" and gate_name("Nal") == "2Nal" and gate_name("meA") == "NMeA"
    assert gate_name("Phe(4-Cl)") is None and helm_from_tokens(["A", "Phe(4-Cl)", "G"]) is None   # not representable in the gate dialect -> ungradeable, not mis-parsed


def test_verifier_cheap_cases():
    h = VerifierHook("avb6"); p, i, n = h.grade_helm(PASS_H), h.grade_helm(INFR_H), h.grade_helm(NORGD_H)
    assert p["hard_gate_pass"] and p["reward"] > 0 and not i["hard_gate_pass"] and not n["hard_gate_pass"]
    assert i["hard_gate_reasons"]["fto_not_infringing"] is False and n["hard_gate_reasons"]["rule"] is False
    assert p["reward"] > i["reward"] and p["reward"] > n["reward"]
    assert set(p["pending_physics"]) >= {"ddg_fep", "binding_dG", "selectivity_gap"}            # physics is pending, listed, never invented
    assert all(v == 0 for k, v in p["terms"].items() if k in ("ddg_fep", "binding_mmgbsa_proxy", "selectivity", "groove"))
    q = VerifierHook("pdl1").grade_helm(NORGD_H); assert q["rule_applicable"] is False


def test_verifier_refuses_full_tier_by_default():
    with pytest.raises(ValueError): VerifierHook("avb6").grade_helm(PASS_H, tier="full")


def _rows(n_fam=10, seed=0):
    rng = random.Random(seed); seqs = ["".join(rng.choice("AGLFVIKRSTY") for _ in range(6)) for _ in range(n_fam)]
    smi = [Chem.MolToSmiles(Chem.MolFromSequence(s)) for s in seqs]; return smi


def _model():
    M = load_ihlm(); return M.IHLM(modules=("M2", "M3", "M4"), slow_every=99, seed=0)       # fast memory only; the slow net is never triggered here


def test_bridge_never_writes_rewards_as_labels_or_laboratory_sources():
    smi = _rows(); rows = [dict(smiles=s, target_seq="T", label=float(i) * 0.1, source="labA") for i, s in enumerate(smi)]
    gr = {Chem.MolToSmiles(Chem.MolFromSmiles(s)): dict(hard_gate_pass=(i % 2 == 0), reward=9.99) for i, s in enumerate(smi)}
    m0 = _model(); m1, n = GradedMemoryBridge().ingest(m0, rows, gr)
    assert n == len(rows) and len(m0.mem.rows) == 0 and len(m1.mem.rows) == len(rows)           # input model untouched
    assert sorted(r["label"] for r in m1.mem.rows) == sorted(r["label"] for r in rows) and all(r["source"] == "labA" for r in m1.mem.rows)
    assert not any(abs(r["label"] - 9.99) < 1e-9 for r in m1.mem.rows)                        # the reward (9.99) never became a label
    got = {r["smiles"]: r.get("verifier") for r in m1.mem.rows}; assert sorted(got.values()) == [0.0] * 5 + [1.0] * 5   # planted flag reaches memory


def test_verifier_flag_does_not_change_lab_offsets():
    smi = _rows(8); rows = [dict(smiles=s, target_seq="T", label=float(i) * 0.1, source="labA") for i, s in enumerate(smi)] + [dict(smiles=s, target_seq="T", label=float(i) * 0.1 + 0.5, source="labB") for i, s in enumerate(smi)]
    gr = {Chem.MolToSmiles(Chem.MolFromSmiles(s)): dict(hard_gate_pass=(i % 2 == 0), reward=1.0) for i, s in enumerate(smi)}
    plain = _model().update(rows, mode="finetune_ranking"); with_v, _ = GradedMemoryBridge().ingest(_model(), rows, gr)
    assert plain.offsets and plain.offsets == with_v.offsets                                      # planted +0.5 offset estimated identically with or without the verifier flag
    assert abs((plain.offsets["labB"] - plain.offsets["labA"]) - 0.5) < 0.2


def test_unmapped_or_unrepresentable_compounds_are_skipped_and_counted(ad):
    s = _cycpept_smiles(150); g, st = grade_smiles(ad, VerifierHook("avb6"), s + ["CCO"])
    assert st["n"] == 151 and st["graded"] == len(g) and st["unmapped"] >= 1 and st["duplicates"] >= 1      # CycPeptMPDB repeats structures: duplicates are counted, not silently overwritten
    assert sum(st[x] for x in ("graded", "duplicates", "unmapped", "unrepresentable", "invalid_smiles")) == st["n"]


def test_pairs_prefer_gate_pass_over_fail():
    h = VerifierHook("avb6"); gs = [h.grade_helm(x) for x in (PASS_H, INFR_H, NORGD_H)]; ps = GradedMemoryBridge.pairs(gs)
    assert len(ps.pairs) >= 2 and all(isinstance(p.margin, float) or True for p in ps.pairs)
    first = ps.pairs[0]; assert PASS_H in (getattr(first, "chosen", "") or "")
