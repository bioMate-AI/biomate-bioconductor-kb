"""Tests for the rule automaton. Run on EC2 (not on the laptop):  CHEMFM_TOK=<tokenizer.json> python -m pytest -x -q test_rules.py   (from allatom_paper/rules/..)."""
import os, sys, json, time, random, collections
import numpy as np
import pytest
from rdkit import Chem

HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, ".."))
from rules import golden, spec, vocab as V, tracker as T
from rules.constraint import ChemFMConstraint

TOK = os.environ.get("CHEMFM_TOK", os.path.join(os.environ.get("CHEMFM_DIR", "."), "tokenizer.json"))
RULES = os.environ.get("SAR_RULES", os.path.join(HERE, "..", "..", "kb_audit", "peptide_sar_rules_v1.json"))
MAXLEN = 500


@pytest.fixture(scope="module")
def voc(): return V.load(TOK)


@pytest.fixture(scope="module")
def con(voc): return ChemFMConstraint(voc, max_len=MAXLEN)


@pytest.fixture(scope="module")
def rows(): return golden.make()


def test_golden_size_and_labels(rows):
    c = collections.Counter(r["kind"] for r in rows)
    assert len(rows) >= 2000, c
    for r in rows:
        m = Chem.MolFromSmiles(r["smiles"])
        if r["kind"] == "invalid": assert m is None
        elif r["kind"] == "sat": assert spec.satisfies(m)
        else: assert m is not None and not spec.satisfies(m)


def test_spec_equals_pilot3(rows):
    sys.path.insert(0, os.path.join(HERE, "..", "..", "generation_pilot"))
    try: import gen_pilot
    except Exception as e: pytest.skip(f"gen_pilot not importable: {e}")
    for r in rows:
        m = Chem.MolFromSmiles(r["smiles"])
        assert bool(gen_pilot.satisfies(m)) == bool(spec.satisfies(m)), r["smiles"]


def test_encode_matches_hf(rows):
    try: from transformers import AutoTokenizer
    except Exception: pytest.skip("transformers not installed")
    d = os.path.dirname(TOK)
    try: tok = AutoTokenizer.from_pretrained(d)
    except Exception as e: pytest.skip(f"HF tokenizer not loadable: {e}")
    voc = V.load(TOK); bad = 0; n = 0
    for r in rows[:600]:
        if r["kind"] == "invalid": continue
        mine = voc.encode(r["smiles"]); hf = [i for i in tok(r["smiles"], add_special_tokens=False)["input_ids"]]
        n += 1; bad += (mine != hf)
    assert bad == 0, f"{bad}/{n} strings tokenised differently from the HF tokenizer"


def _ids(voc, s): return voc.encode(s)


def test_soundness_false_prune_rate_zero(con, voc, rows):
    """for every string that satisfies C, every true next token (and the final eos) is allowed by the mask at its prefix."""
    pruned = []; positions = 0; strings = 0
    for r in rows:
        if r["kind"] != "sat": continue
        ids = _ids(voc, r["smiles"]); st = con.init_state(); strings += 1
        for k, tid in enumerate(ids):
            m = con.mask(st); positions += 1
            if not m[tid]: pruned.append((r["smiles"], k, voc.id2tok[tid])); break
            assert con.advance(st, tid)
        else:
            positions += 1
            if not con.mask(st)[con.eos]: pruned.append((r["smiles"], len(ids), "<eos>"))
    rate = len(pruned) / max(1, strings)
    print(f"false-prune: {len(pruned)} strings of {strings} ({positions} positions); first: {pruned[:5]}")
    assert not pruned, pruned[:5]


def test_eos_gate_exact(con, voc, rows):
    """eos allowed iff the complete string satisfies C (RDKit); for valid_bad and invalid strings eos is never allowed at the end."""
    for r in rows:
        if r["kind"] == "invalid": continue
        ids = _ids(voc, r["smiles"]); st = con.init_state(ids)
        assert bool(con.mask(st)[con.eos]) == (r["kind"] == "sat"), (r["smiles"], r["kind"])


def test_invalid_strings_are_cut_or_never_finish(con, voc, rows):
    cut = 0; n = 0
    for r in rows:
        if r["kind"] != "invalid": continue
        n += 1
        try: ids = _ids(voc, r["smiles"])
        except ValueError: cut += 1; continue
        st = con.init_state(); done = False
        for tid in ids:
            if not con.mask(st)[tid]: cut += 1; done = True; break
            con.advance(st, tid)
        if not done: assert not con.mask(st)[con.eos], r["smiles"]   # never accepted
    print(f"invalid strings cut by the mask before the end: {cut}/{n}")


def test_fast_equals_ref(con, voc, rows):
    rng = random.Random(1); sel = rng.sample([r for r in rows if r["kind"] != "invalid"], 40); n = 0
    for r in sel:
        ids = _ids(voc, r["smiles"]); st = con.init_state()
        for k, tid in enumerate(ids):
            if k % 5 == 0:
                a = con.mask(st); b = con.mask_ref(st); n += 1
                assert (a == b).all(), (r["smiles"], k, [voc.id2tok[i] for i in np.where(a != b)[0]])
            con.advance(st, tid)
    assert n > 100


def test_nme_lower_bound_sound(voc, rows):
    """tracker N-methyl lower bound at every prefix <= the true final count (spec.mol_stats), for canonical and random-order SMILES."""
    for r in rows:
        if r["kind"] == "invalid": continue
        m = Chem.MolFromSmiles(r["smiles"]); final = spec.mol_stats(m)[1]; st = T.Tracker()
        for tid in _ids(voc, r["smiles"]):
            assert st.advance(voc.id2tok[tid])
            assert st.nme_lower_bound() <= final, (r["smiles"], st.string(), st.nme_lower_bound(), final)
        assert st.mass <= __import__("rdkit.Chem.Descriptors", fromlist=["x"]).MolWt(m) + 1e-6


def test_by_construction_guided_walk(con, voc, rows):
    """end-to-end: start at 60% of a satisfying string, follow its true next token 97% of the time (else a random allowed token), take eos whenever allowed after the original ends.
    Every string that ends on eos satisfies C (RDKit). Completion count is reported; the walk diverges from the golden path so the eos gate is exercised on novel strings."""
    rng = random.Random(3); sat = [r for r in rows if r["kind"] == "sat"]; done = 0; tried = 0; novel = 0
    for r in rng.sample(sat, 150):
        ids = _ids(voc, r["smiles"]); k0 = int(0.6 * len(ids)); st = con.init_state(ids[:k0]); out = list(ids[:k0]); tried += 1
        for step in range(MAXLEN):
            m = con.mask(st); pos = len(out)
            if pos >= len(ids) and m[con.eos]: break
            idx = np.where(m)[0]
            if len(idx) == 0: out = None; break
            if pos < len(ids) and m[ids[pos]] and rng.random() < 0.97: tid = ids[pos]
            else: tid = int(rng.choice(list(idx[idx != con.eos]) or list(idx)))
            if tid == con.eos: break
            con.advance(st, tid); out.append(tid)
        else: out = None
        if out is not None and con.mask(st)[con.eos]:
            done += 1; sm = st.string(); assert spec.satisfies_smiles(sm), sm; novel += (sm != r["smiles"])
    print(f"guided walks completed {done}/{tried} (novel strings: {novel})")
    assert done >= 20


def test_budget_forces_closers(voc):
    c = ChemFMConstraint(voc, max_len=12)
    st = c.init_state(voc.encode("CC(C(C(C"))        # 3 open branches, n = 8, remaining 4, needs >= 3 closers + eos = 4
    m = c.mask(st); allowed = {voc.id2tok[i] for i in np.where(m)[0]}
    assert allowed <= {")"} or allowed == set(), allowed
    st2 = c.init_state(voc.encode("CC(C(C(C"))
    assert c.advance(st2, voc.tok2id[")"])


AP = os.path.join(HERE, "..")


def test_soft_none_is_zero_and_default(voc):
    c = ChemFMConstraint(voc); st = c.init_state(voc.encode("CC"))
    assert not c.soft_logits(st).any()
    from rules.soft import SoftSource
    c2 = ChemFMConstraint(voc, lam_soft=1.0, soft=SoftSource.none()); assert not c2.soft_logits(st).any()


def test_soft_literature_sources_signed(voc):
    from rules.soft import SoftSource
    st = ChemFMConstraint(voc).init_state(voc.encode("CC"))
    c = ChemFMConstraint(voc, lam_soft=0.5, soft=SoftSource.literature_uniform()); s = c.soft_logits(st)
    assert s[voc.tok2id["N"]] < 0 and s[voc.tok2id["O"]] < 0 and s[voc.tok2id["C"]] > 0
    kb = SoftSource.from_knowledge(os.path.join(AP, "knowledge", "knowledge_kb_v1.json"))
    assert kb.weights["polar"] < 0 and kb.weights["nme"] > 0                      # net carbon (logP) weight of the KB is 0: its clogP(+) and alogP(-) rules cancel
    c = ChemFMConstraint(voc, lam_soft=0.5, soft=kb); s = c.soft_logits(st)
    assert s[voc.tok2id["N"]] < 0 and s[voc.tok2id["O"]] < 0


def test_soft_groupA_descriptive_labelled_and_disjoint(voc):
    from rules.soft import SoftSource, assert_sources_disjoint, forbidden_from_groups
    src = SoftSource.groupA_descriptive(os.path.join(AP, "rules_mining", "groupA_sensitivity.json"))
    assert "unvalidated" in src.status and set(src.mined_from) == {"2020_Townsend", "2021_Kelly"}
    forb = forbidden_from_groups(os.path.join(AP, "track_e", "source_groups_v2.json"))
    assert len(forb) == 18 and assert_sources_disjoint(src, forb)
    c = ChemFMConstraint(voc, lam_soft=0.5, soft=src, forbidden_sources=forb)       # constructs
    bad = SoftSource("x", "x", {"polar": 1.0, "carbon": 1.0, "nme": 0.0}, mined_from=(forb[0],))
    with pytest.raises(AssertionError): ChemFMConstraint(voc, lam_soft=0.5, soft=bad, forbidden_sources=forb)
    assert src.weights["polar"] < 0 and src.weights["carbon"] > 0 and src.weights["nme"] > 0     # descriptive directions agree with the textbook signs


def test_soft_nme_nudge_and_mask_independence(voc):
    from rules.soft import SoftSource
    c = ChemFMConstraint(voc, lam_soft=1.0, soft=SoftSource.literature_uniform())
    st = c.init_state(voc.encode("CC(C)C[C@H](C)C(=O)N"))              # amide N with one neighbour (the carbonyl C)
    assert c.soft_logits(st)[voc.tok2id["("]] > 0
    st2 = c.init_state(voc.encode("CC(C)C[C@H](C)C(=O)N("))
    assert c.soft_logits(st2)[voc.tok2id["C"]] > c.soft_logits(st2)[voc.tok2id["N"]]
    m = c.mask(st); s = c.soft_logits(st)
    assert (m == ChemFMConstraint(voc).mask(st)).all()                  # soft rules never change the hard mask


def test_overhead_report(con, voc, rows):
    ids = _ids(voc, [r for r in rows if r["kind"] == "sat"][0]["smiles"]); st = con.init_state(); tf = tr = 0.0; n = 0
    for tid in ids:
        t0 = time.perf_counter(); con.mask(st); tf += time.perf_counter() - t0
        t0 = time.perf_counter(); con.mask_ref(st); tr += time.perf_counter() - t0; n += 1
        con.advance(st, tid)
    print(f"mask overhead per step: fast {1000*tf/n:.2f} ms, ref {1000*tr/n:.2f} ms ({n} steps)")
    assert tf <= tr



def test_contract_adapter(voc, rows):
    from rules.constraint import RuleAutomaton
    import contracts
    ra = RuleAutomaton(ChemFMConstraint(voc, max_len=MAXLEN))
    assert isinstance(ra, contracts.Constraint)
    vocab_list = [voc.id2tok.get(i, "") for i in range(voc.V)]
    sat = [r for r in rows if r["kind"] == "sat"][:25]
    for r in sat:
        st = ra.init_state()
        for tid in _ids(voc, r["smiles"]):
            tok = voc.id2tok[tid]; m = ra.mask(st, vocab_list)
            assert len(m) == len(vocab_list) and m[tid], (r["smiles"], tok)
            st = ra.advance(st, tok)
        assert ra.is_complete(st) and ra.check(r["smiles"])
        assert ra.mask(st, vocab_list)[voc.eos]
    bad = [r for r in rows if r["kind"] == "valid_bad"][:25]
    for r in bad:
        assert not ra.check(r["smiles"])
        st = ra.init_state()
        for tid in _ids(voc, r["smiles"]): st = ra.advance(st, voc.id2tok[tid])
        assert not ra.is_complete(st)
    with pytest.raises(ValueError): ra.advance(ra.init_state(), ")")
    assert len(ra.soft_logits(ra.init_state(), vocab_list)) == len(vocab_list)


def test_bracket_grammar_strict(voc):
    """junk bracket contents seen in the dead-end dump are now illegal; ordinary peptide brackets are legal."""
    for good in ["[C@H]", "[C@@H]", "[nH]", "[NH3+]", "[O-]", "[N+]", "[C@@H]", "[Cl-]", "[S@]"]:
        st = T.Tracker(); ok = all(st.advance(voc.id2tok[i]) for i in voc.encode("C" + good)); assert ok and st.br is None, good
    for bad in ["[C@HH", "[C@@@", "[C@H2H", "[N++-", "[P+@", "[C@H+@", "[CH@", "[NH3+-", "[13C", "[Na", "[Li", "[h", "[he", "[Si", "[131Li", "[H"]:
        st = T.Tracker(); r = True
        for i in voc.encode("C" + bad):
            r = st.advance(voc.id2tok[i])
            if not r: break
        assert not r, bad


def test_bracket_mass_charged_at_element(voc):
    c = ChemFMConstraint(voc, max_len=MAXLEN)
    st = c.init_state(voc.encode("C[")); m0 = st.mass
    assert c.advance(st, voc.tok2id["Cl"]) and st.mass > m0 + 30          # Cl charged at the element token, before ']'
    st2 = T.Tracker(); [st2.advance(voc.id2tok[i]) for i in voc.encode("C" * 115)]    # mass ~ 1381
    st2.advance("["); assert not c.mask(st2)[voc.tok2id["Cl"]] or st2.mass + 35.5 <= 1400


def test_language_restriction_loses_no_real_peptide(voc, rows):
    """every satisfying golden string AND every CycPeptMPDB structure parsed locally uses only the allowed language (no false-prune is possible from the restriction)."""
    import csv
    allowed = {"C", "N", "O", "S", "P", "F", "Cl", "Br", "I"}
    for r in rows:
        if r["kind"] == "invalid": continue
        m = Chem.MolFromSmiles(r["smiles"]); assert {a.GetSymbol() for a in m.GetAtoms()} <= allowed and not any(a.GetIsotope() for a in m.GetAtoms())
    p = os.environ.get("CPM_CSV")
    if p and os.path.exists(p):
        bad = 0; n = 0
        for row in csv.DictReader(open(p, newline="")):
            m = Chem.MolFromSmiles(row.get("SMILES") or "")
            if m is None: continue
            n += 1; bad += (not {a.GetSymbol() for a in m.GetAtoms()} <= allowed) or any(a.GetIsotope() for a in m.GetAtoms())
        print(f"CycPeptMPDB structures outside the restricted language: {bad}/{n}"); assert bad == 0


def test_lookahead_nme_sound_and_effective(voc, rows):
    """(a) the tightened look-ahead never prunes the true next token of a satisfying string (false-prune 0 on the whole golden set; the main false-prune test already runs with it);
    (b) it prunes states that provably cannot reach N-Me >= 2 within the weight budget: a string at mass ~1385 with no N-methyl amide and no extendable N."""
    c = ChemFMConstraint(voc, max_len=MAXLEN); c0 = ChemFMConstraint(voc, max_len=MAXLEN, lookahead_nme=False)
    st = T.Tracker()
    for t in voc.encode("C" * 115): st.advance(voc.id2tok[t])          # mass ~1381, nothing built, no N at all
    assert st.mass > 1380 and st.nme_missing_new(2) == 2
    assert not st.feasible(1400.0, 6, 500 - st.n, 2)                    # 2 missing N-Me amides need >= 52 more weight units
    assert st.feasible(1400.0, 6, 500 - st.n, 0)                        # the old rule still allows it
    sat = [r for r in rows if r["kind"] == "sat"][:120]
    for r in sat:
        st = c.init_state()
        for tid in _ids(voc, r["smiles"]):
            assert c.mask(st)[tid], r["smiles"]; c.advance(st, tid)
        assert c.mask(st)[c.eos]
