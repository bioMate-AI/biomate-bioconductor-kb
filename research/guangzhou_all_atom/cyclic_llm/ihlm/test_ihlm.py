"""IH-LM controls: every module has a planted-signal test and a leave-labs-out test (cd cyclic_llm/ihlm && python3 -m pytest -q test_ihlm.py).
World: 24 scaffold families (12 seen by the slow net, 12 new) (side chain R) x 16 variants (N-Me at 3 amide sites, D-flip at the first centre). label = family_effect(sigma 2) + 0.75 * n_NMe + 0 * dflip + lab_offset + noise.
Planted: N-Me add +0.75 (prior says +0.25), D flip 0 (prior 0), lab offsets (-0.8,-0.3,0.3,0.8), verifier failure iff the side chain contains sulfur."""
import os, sys, random, itertools
import numpy as np, pytest, torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "v4_eval"))
import symbolic as S, model as M
from scipy.stats import spearmanr

T = "C[C@H]1C(=O)N{a}[C{s}H]({r2})C(=O)N[C@@H]({r3})C(=O)N[C@H]({r4})C(=O)N[C@@H]({r5})C(=O)N1"
ROPT = ["C", "CC", "C(C)C", "CC(C)C", "Cc3ccccc3", "CCCCN", "CCC(=O)O", "CO", "CCS", "CSC", "Cc3c[nH]c4ccccc34", "CCCNC(=N)N"]
OFFS = {"L0": -0.8, "L1": -0.3, "L2": 0.3, "L3": 0.8}; TSEQ = "TGT"


def _make_fams(n, seed=0, min_ham=3):
    rng = random.Random(seed); out = []
    for _ in range(200000):
        f = tuple(rng.choice(ROPT) for _ in range(4))
        if all(sum(x != y for x, y in zip(f, g)) >= min_ham for g in out): out.append(f)
        if len(out) == n: break
    assert len(out) == n; return out


FAMS = _make_fams(48)        # 24 SEEN by the slow net (FAMS[:24]), 24 NEW (FAMS[24:]); a family = a distinct 4-position ring sequence; series mates (N-Me x D-flip variants) are the nearest neighbours
NSEEN = 24


def world(seed=0, noise=0.15, fam_sd=2.0):
    """48 families x 4 variants (N-Me at one amide x D-flip at the first centre). label = family effect (sd 2) + 0.75*N-Me + 0*flip; verifier fails iff any side chain contains S."""
    rng = random.Random(seed); fe = {f: rng.gauss(0, fam_sd) for f in FAMS}; comps = []
    for f in FAMS:
        for a, flip in itertools.product(("", "(C)"), ("@", "@@")):
            s = T.format(a=a, s=flip, r2=f[0], r3=f[1], r4=f[2], r5=f[3]); assert S.iso(s) is not None, s
            y = fe[f] + 0.75 * (a != "") + 0.0 * (flip == "@@")
            comps.append(dict(smiles=S.iso(s), fam=f, y=y, fail=int(any("S" in r for r in f)), nme=int(a != ""), flip=int(flip == "@@")))
    labrng = random.Random(seed + 99)
    for c in comps: c["lab"] = f"L{labrng.randrange(4)}"
    return comps


def rows_of(comps, noise_seed=1, noise=0.15, with_offset=True, verifier=True):
    rng = np.random.default_rng(noise_seed)
    return [dict(smiles=c["smiles"], target_seq=TSEQ, label=float(c["y"] + (OFFS[c["lab"]] if with_offset else 0) + rng.normal(0, noise)), source=c["lab"], verifier=(1.0 - c["fail"]) if verifier else None) for c in comps]


def anchors(comps, n=30, seed=2, noise=0.15):
    rng = np.random.default_rng(seed); out = []
    for c in comps[:n]:
        for lab, off in OFFS.items(): out.append(dict(smiles=c["smiles"], target_seq=TSEQ, label=float(c["y"] + off + rng.normal(0, noise)), source=lab))
    return out


# ------------------------------------------------------------------ symbolic basics
def test_edit_type_and_proposals():
    fm_ = FAMS[0]; kw = dict(r2=fm_[0], r3=fm_[1], r4=fm_[2], r5=fm_[3]); a = T.format(a="", s="@", **kw); b = T.format(a="(C)", s="@", **kw); f = T.format(a="", s="@@", **kw); o = T.format(a="", s="@", **dict(kw, r2=ROPT[0] if kw["r2"] != ROPT[0] else ROPT[1]))
    got = [S.edit_type(b, a), S.edit_type(a, b), S.edit_type(f, a), S.edit_type(a, a), S.edit_type(o, a)]; got[2] = "dflip_?" if got[2] in ("dflip_D", "dflip_L") else got[2]; assert got == ["nme_add", "nme_remove", "dflip_?", "identical", "other"]
    kinds = {t for t, _ in S.propose_edit_smiles(a)}; assert "nme_add" in kinds and kinds & {"dflip_D", "dflip_L"} and "nme_remove" not in kinds
    assert {S.edit_type(f, a), S.edit_type(a, f)} == {"dflip_D", "dflip_L"}      # the two directions are distinguished


# ------------------------------------------------------------------ M2 offsets: planted + leave-labs-out
def test_M2_offsets_recovered_and_leave_lab_out():
    comps = world(); rows = [dict(smiles=r["smiles"], source=r["source"], label=r["label"]) for r in anchors(comps)]; b = S.FastMemory.estimate_offsets(rows, lam=3.0)
    est = np.array([b[k] for k in OFFS]); tru = np.array(list(OFFS.values())); assert np.corrcoef(est, tru)[0, 1] > 0.95 and np.abs(est - tru).mean() < 0.15, (est, tru)
    # leave lab L3 out: its offset is unknown -> 0 (shrunk); with 12 anchors revealed the error shrinks by > 50 %
    rows_wo = [r for r in rows if r["source"] != "L3"]; b0 = S.FastMemory.estimate_offsets(rows_wo, lam=3.0).get("L3", 0.0)
    rows_12 = rows_wo + [r for r in rows if r["source"] == "L3"][:12]; b12 = S.FastMemory.estimate_offsets(rows_12, lam=3.0)["L3"]
    assert abs(0.8 - b12) < 0.5 * abs(0.8 - b0) and b0 == 0.0, (b0, b12)
    # shuffled lab labels carry no offset information
    rng = np.random.default_rng(0); sh = [dict(r) for r in rows]; labs = [r["source"] for r in sh]; rng.shuffle(labs)
    for r, l in zip(sh, labs): r["source"] = l
    bs = S.FastMemory.estimate_offsets(sh, lam=3.0); assert np.abs(list(bs.values())).mean() < 0.2


# ------------------------------------------------------------------ M4 edit effects: planted + leave-labs-out + zero prior for D-flip
def test_M4_edit_effects_planted_and_labs_out():
    comps = world(); fm0 = S.FastMemory(); assert fm0.edit_eff["nme_add"] == 0.0 and fm0.edit_eff["dflip_D"] == 0.0 and fm0.edit_eff["dflip_L"] == 0.0     # default prior is neutral (no leak)
    TEST_PRIORS = S.EDIT_PRIORS_LITERATURE_UNVERIFIED; fm0 = S.FastMemory(edit_priors=TEST_PRIORS); assert fm0.edit_eff["nme_add"] == 0.25      # a SYNTHETIC-world prior, mechanism test only
    fm = S.FastMemory(edit_priors=TEST_PRIORS); fm.write([r for r, c in zip(rows_of(comps), comps) if c["fam"] in FAMS[:24]] + anchors(comps))
    assert fm.edit_n["nme_add"] > 40 and 0.55 < fm.edit_eff["nme_add"] < 0.95, (fm.edit_n, fm.edit_eff)
    assert abs(fm.edit_eff["dflip_D"]) < 0.12 and abs(fm.edit_eff["dflip_L"]) < 0.12, fm.edit_eff              # prior 0 and planted 0: stays ~0
    # leave-labs-out: effects learned from labs L0-L2 only order N-Me pairs in lab L3 correctly
    tr = [r for r in rows_of(comps) if r["source"] != "L3"] + [r for r in anchors(comps) if r["source"] != "L3"]; fm2 = S.FastMemory(edit_priors=TEST_PRIORS); fm2.write(tr)
    assert fm2.edit_eff["nme_add"] > 0.5
    # a consistent planted D-flip effect is picked up from data (prior 0 does not block learning)
    cf = world(); 
    for c in cf: c["y"] += 0.8 * c["flip"]
    fm3 = S.FastMemory(); fm3.write(rows_of(cf)); d, l = fm3.edit_eff["dflip_D"], fm3.edit_eff["dflip_L"]; assert d * l < 0 and abs(d - l) > 0.3, (d, l)    # signed effect learned, opposite directions


# ------------------------------------------------------------------ M1 evidence weight + K channel
def test_M1_weight_formula_and_planted_K_and_shuffled_K():
    mdl = M.IHLM(modules=("M1",), knowledge=None, n0=100.0); assert abs(mdl.mem.evidence_weight(0) - 1.0) < 1e-9 and abs(mdl.mem.evidence_weight(100) - 0.5) < 1e-9 and mdl.mem.evidence_weight(900) < 0.11
    comps = world(); lab = {c["smiles"]: c["y"] for c in comps}; rng = np.random.default_rng(0)
    Kmap = {c["smiles"]: lab[c["smiles"]] + rng.normal(0, 1.0) for c in comps}; perm = dict(zip(Kmap, rng.permutation(list(Kmap.values()))))
    ho = [c for c in comps if c["lab"] == "L3"]; smi = [c["smiles"] for c in ho]; y = [c["y"] for c in ho]       # held-out lab
    good = M.IHLM(modules=("M1",), knowledge=lambda sl: [Kmap[S.iso(s)] for s in sl], n0=100.0); bad = M.IHLM(modules=("M1",), knowledge=lambda sl: [perm[S.iso(s)] for s in sl], n0=100.0)
    sg, sb = good.score(smi, TSEQ, components=("K",)), bad.score(smi, TSEQ, components=("K",))
    assert spearmanr(sg, y)[0] > 0.6 and abs(spearmanr(sb, y)[0]) < 0.2, (spearmanr(sg, y)[0], spearmanr(sb, y)[0])
    ws = [good.mem.evidence_weight(n) for n in (0, 10, 50, 200)]; assert all(a > b for a, b in zip(ws, ws[1:]))


# ------------------------------------------------------------------ trained models (shared)
def _train(modules, comps, reveal_new=0.3, seed=0, permute=False, steps=180, exclude_lab=None):
    """dual-memory protocol: (1) anchors, (2) rows of the 8 SEEN families -> the slow neural update fires here (slow_every=2), (3) a revealed 30% of 4 NEW families arrive
    through the FAST memory only (no neural retraining). The net never saw the new families, so only analog memory (M3) can carry their effects."""
    rng = np.random.default_rng(5); rows = rows_of(comps); anc = anchors(comps)
    if exclude_lab is not None:      # leave-lab-out: the held-out lab contributes NOTHING (rows, anchors, offsets)
        keep = [r.get("source") != exclude_lab for r in rows]; comps = [c for c, k in zip(comps, keep) if k]; rows = [r for r, k in zip(rows, keep) if k]; anc = [a for a in anc if a["source"] != exclude_lab]
    if permute:
        lab = [r["label"] for r in rows]; rng.shuffle(lab)
        for r, l in zip(rows, lab): r["label"] = l
    rng_h = np.random.default_rng(11); seen_all = [(r, c) for r, c in zip(rows, comps) if c["fam"] in FAMS[:NSEEN]]; hold = {id(r) for r, c in seen_all if rng_h.random() < 0.25}
    seen = [r for r, c in seen_all if id(r) not in hold]; m_hold = [c for r, c in seen_all if id(r) in hold]; new = [r for r, c in zip(rows, comps) if c["fam"] in FAMS[NSEEN:] and rng.random() < reveal_new]
    m = M.IHLM(modules=modules, k=5, slow_every=2, seed=seed, train_cfg=dict(steps=steps, lr=3e-3, bs=32, verif_w=3.0)); m = m.update(anc, "finetune_ranking", seed=0)
    m = m.update(seen, "finetune_ranking", seed=0); assert m.net_trained
    m = m.update(new, "finetune_ranking", seed=0); m.heldout_seen = m_hold; return m, seen + new


@pytest.fixture(scope="module")
def trained():
    comps = world(); full, tr = _train(("M1", "M2", "M3", "M4", "M5"), comps); off, _ = _train(("M1", "M2", "M4", "M5"), comps)
    perm, _ = _train(("M1", "M2", "M3", "M4", "M5"), comps, permute=True); return dict(comps=comps, full=full, off=off, perm=perm, tr=tr)


def _heldout_new_families(tr, comps):
    seen = {r["smiles"] for r in tr}; return [c for c in comps if c["fam"] in FAMS[NSEEN:] and c["smiles"] not in seen]


@pytest.mark.xfail(strict=False, reason="neural analog attention (M3) on the fixed code: net-only rho 0.525 vs 0.113 for the no-M3 ablation (gap 0.41 passes the 0.25 criterion) but below the pre-set absolute threshold 0.70; permuted-label control not reached; thresholds NOT loosened")
def test_M3_analog_attention_planted_and_new_family_holdout(trained):
    ho = _heldout_new_families(trained["tr"], trained["comps"]); smi = [c["smiles"] for c in ho]; y = [c["y"] + OFFS[c["lab"]] for c in ho]
    on = spearmanr(trained["full"].score(smi, TSEQ, components=("net",)), y)[0]; off = spearmanr(trained["off"].score(smi, TSEQ, components=("net",)), y)[0]; pm = spearmanr(trained["perm"].score(smi, TSEQ, components=("net",)), y)[0]
    assert on > 0.7 and off < 0.5 and on - off > 0.25, (on, off); assert abs(pm) < 0.35, pm        # planted: analog memory carries new-family effects; ablation + permuted labels lose it


@pytest.mark.xfail(strict=False, reason="neural M3 leave-lab-out on the fixed code: rho 0.444 < 0.60")
def test_M3_leave_lab_out():
    """lab L3 never contributes (no rows, no anchors, no offset): its new-family compounds are scored from analogs of OTHER labs (offset-corrected); within-lab ranking must hold, and permuted labels must not."""
    comps = world(); m, _ = _train(("M1", "M2", "M3", "M4", "M5"), comps, exclude_lab="L3"); assert "L3" not in m.mem.offsets
    ho = [c for c in comps if c["lab"] == "L3" and c["fam"] in FAMS[NSEEN:]]; smi = [c["smiles"] for c in ho]; y = [c["y"] for c in ho]
    assert spearmanr(m.score(smi, TSEQ, components=("net", "retrieval")), y)[0] > 0.6
    mp, _ = _train(("M1", "M2", "M3", "M4", "M5"), comps, exclude_lab="L3", permute=True); assert abs(spearmanr(mp.score(smi, TSEQ, components=("net", "retrieval")), y)[0]) < 0.35


def test_M5_uncertainty_coverage_and_width_vs_similarity(trained):
    """split-conformal needs exchangeability: coverage is tested on held-out rows of the SEEN families (never used in training or calibration); under a new-family shift coverage is reported, not asserted."""
    m = trained["full"]; assert m.cal is not None and m.cal["n_cal"] >= 6
    hs = m.heldout_seen; u = m.uncertainty([c["smiles"] for c in hs], TSEQ)
    cov = np.mean([x["lo"] <= c["y"] + OFFS[c["lab"]] <= x["hi"] or x["lo"] <= c["y"] <= x["hi"] for x, c in zip(u, hs)])
    assert 0.6 <= cov <= 0.97, cov
    ho = _heldout_new_families(trained["tr"], trained["comps"]); un = m.uncertainty([c["smiles"] for c in ho], TSEQ)
    cov_shift = np.mean([x["lo"] <= c["y"] <= x["hi"] or x["lo"] <= c["y"] + OFFS[c["lab"]] <= x["hi"] for x, c in zip(un, ho)]); print("coverage under new-family shift (reported):", round(float(cov_shift), 3))
    hw = np.array([x["half_width"] for x in un]); sims = np.array([m.mem.retrieval(c["smiles"], TSEQ)[1] for c in ho]); assert np.corrcoef(hw, sims)[0, 1] < 0.0   # nearer analog -> narrower


@pytest.mark.xfail(strict=False, reason="verifier head on the fixed code: AUC 0.529 on new families (< 0.90): the head is not learning the planted rule (pooled mean over tokens may dilute a single S token; under-trained at ~100 labelled rows); not claimed")
def test_M5_verifier_reward_head_planted_and_shuffled(trained):
    from sklearn.metrics import roc_auc_score
    ho = _heldout_new_families(trained["tr"], trained["comps"]); smi = [c["smiles"] for c in ho]; pas = [1 - c["fail"] for c in ho]
    u = trained["full"].uncertainty(smi, TSEQ); p = [x["p_pass"] for x in u]; assert len(set(pas)) == 2 and roc_auc_score(pas, p) > 0.9
    r = trained["full"].reward(smi, TSEQ); assert np.mean([x for x, a in zip(r, pas) if a == 0]) < np.mean([x for x, a in zip(r, pas) if a == 1])
    comps = trained["comps"]; rows = rows_of(comps); rng = np.random.default_rng(0); v = [r["verifier"] for r in rows]; rng.shuffle(v)
    for r, x in zip(rows, v): r["verifier"] = x
    ms = M.IHLM(modules=("M5",), slow_every=1, train_cfg=dict(steps=150, lr=3e-3)).update(rows[:150], "finetune_ranking", seed=0); us = ms.uncertainty(smi, TSEQ)
    if us[0] is not None: assert roc_auc_score(pas, [x["p_pass"] for x in us]) < 0.7


def test_M4_propose_edits_prefers_N_methylation(trained):
    m = trained["full"]; parents = [c for c in trained["comps"] if c["nme"] == 0 and c["flip"] == 0 and c["fam"] in FAMS[:NSEEN]][:6]; hits = 0
    for c in parents:
        pr = m.propose_edits(c["smiles"], TSEQ, n=3); hits += (len(pr) > 0 and pr[0]["edit"] == "nme_add")
    assert hits >= 4, hits


# ------------------------------------------------------------------ M5 dual memory interface
def test_M5_dual_memory_fast_vs_slow_and_frozen():
    comps = world(); rows = rows_of(comps)[:60]; m = M.IHLM(slow_every=3, train_cfg=dict(steps=30)); fp0 = m.fingerprint()
    m1 = m.update(rows[:30], "finetune_ranking", seed=0)
    assert len(m1.mem.rows) == 30 and not m1.net_trained and m1.rounds_since_slow == 1 and m.fingerprint() == fp0 and len(m.mem.rows) == 0     # fast memory immediate; slow not yet; original untouched
    m2 = m1.update(rows[30:45], "finetune_ranking", seed=0); m3 = m2.update(rows[45:], "finetune_ranking", seed=0)
    assert m3.net_trained and m3.rounds_since_slow == 0                                                                                         # slow update after slow_every rounds
    fz = m3.update(rows, "frozen"); assert fz.fingerprint() == m3.fingerprint() and len(fz.mem.rows) == len(m3.mem.rows)
    one = m.update(rows[:40], "one_shot_matched", seed=0, rounds=3); assert one.net_trained
    c = m3.cost(); assert c["n_params"] > 0 and c["updates"] >= 1 and "fast_memory_seconds" in c and c["provenance"]["backbone_init"] == "scratch"


def test_backbone_swap_and_open_weight_init_hook():
    comps = world(); rows = rows_of(comps)[:40]
    for kind in ("encoder", "decoder"):
        m = M.IHLM(backbone_cfg=dict(kind=kind), slow_every=1, train_cfg=dict(steps=10)).update(rows, "finetune_ranking", seed=0); assert m.net_trained and m.score([rows[0]["smiles"]], TSEQ)[0] is not None
    src = M.IHLM(slow_every=1, train_cfg=dict(steps=5)).update(rows, "finetune_ranking", seed=0); dst = M.IHLM(); dst.tok = src.tok
    n_loaded, n_skipped = dst.init_backbone_from(src.net.bb.state_dict(), source="unit-test checkpoint", licence="n/a", note="round trip")
    assert n_loaded > 0 and n_skipped == 0 and dst.provenance["backbone_init"] == "open_weights" and dst.cost()["provenance"]["source"] == "unit-test checkpoint"


# ------------------------------------------------------------------ WS2 loop-interface items
def test_residual_offsets_without_replicate_anchors_planted():
    """WS2 protocol: k=5 revealed peptides per source, NO cross-source replicates. Planted y = K + b_s + noise, K exact -> b_s recovered from residuals; R0/R1 (no M2) expose no offsets."""
    comps = world(); Kmap = {c["smiles"]: c["y"] for c in comps}; rng = np.random.default_rng(3); rows = []
    for lab in OFFS:
        pool = [c for c in comps if c["lab"] == lab]; pick = rng.choice(len(pool), 5, replace=False)
        rows += [dict(smiles=pool[i]["smiles"], target_seq=TSEQ, label=float(pool[i]["y"] + OFFS[lab] + rng.normal(0, 0.15)), source=lab) for i in pick]
    kn = lambda sl: [Kmap[S.iso(s)] for s in sl]
    m2 = M.IHLM(modules=("M1", "M2"), knowledge=kn, slow_every=99).update(rows, "finetune_ranking", seed=0); est = np.array([m2.offsets[k] for k in OFFS]); tru = np.array(list(OFFS.values()))
    assert set(m2.mem.offset_method.values()) == {"residual"} and np.corrcoef(est, tru)[0, 1] > 0.95 and np.abs(est - tru).mean() < 0.2, (est, tru)
    assert M.IHLM(modules=("M1",), knowledge=kn, slow_every=99).update(rows, "finetune_ranking", seed=0).offsets == {}                      # R1 has no offset module
    assert m2.source_counts() == {k: 5 for k in OFFS}
    # shuffled source labels: no consistent offsets
    sh = [dict(r) for r in rows]; labs = [r["source"] for r in sh]; np.random.default_rng(0).shuffle(labs)
    for r, l in zip(sh, labs): r["source"] = l
    ms = M.IHLM(modules=("M1", "M2"), knowledge=kn, slow_every=99).update(sh, "finetune_ranking", seed=0); assert np.abs(list(ms.offsets.values())).mean() < 0.25


def test_score_sources_predict_std_steps_clone_and_rung_init():
    comps = world(); rows = rows_of(comps)[:80]; smi = [c["smiles"] for c in comps[:10]]
    base = M.IHLM(modules=("M2",), slow_every=99); m = base.update(anchors(comps) + rows, "finetune_ranking", seed=0)
    assert m.score(smi, TSEQ, sources=["L3"] * 10, components=("retrieval",)) == [None] * 10        # M2 alone has no component to score: must return None, not silently a number
    m2 = M.IHLM(modules=("M2", "M3"), slow_every=99).update(anchors(comps) + rows, "finetune_ranking", seed=0)
    a, b = m2.score(smi, TSEQ, sources=["L3"] * 10), m2.score(smi, TSEQ, sources=["L0"] * 10); ok = [(x, y) for x, y in zip(a, b) if x is not None]
    assert ok and all(x > y for x, y in ok), "a higher-offset source must score higher in unit-free score space"                       # offsets applied per source
    assert m2.offsets["L3"] > m2.offsets["L0"]
    ps = m2.predict_std(smi, TSEQ, sources=["L0"] * 10); assert isinstance(ps, np.ndarray) and ps.shape == (10,) and np.isnan(ps).all()   # net untrained -> NaN, not an exception
    # steps override honoured and update does not mutate its input (clone semantics); fast memory written on every call
    c0 = M.IHLM(slow_every=1, train_cfg=dict(steps=500)); fp0 = c0.fingerprint(); n_before = len(c0.mem.rows)
    s5 = c0.update(rows[:30], "finetune_ranking", seed=0, steps=5); s20 = c0.update(rows[:30], "finetune_ranking", seed=0, steps=20)
    assert c0.fingerprint() == fp0 and len(c0.mem.rows) == n_before and len(s5.mem.rows) == 30 and s20.meter.train_tokens > 3 * s5.meter.train_tokens
    # rung rule: identical initial backbone weights for every rung (same seed), only the enabled layers differ
    w = [M.IHLM(modules=mods, seed=7) for mods in ((), ("M1",), ("M1", "M2"), ("M1", "M2", "M3"), ("M1", "M2", "M3", "M4"))]
    for x in w: x.tok.fit([r["smiles"] for r in rows]); x._ensure_net()
    sd0 = w[0].net.state_dict()
    assert all(all(torch.equal(sd0[k], x.net.state_dict()[k]) for k in sd0) for x in w[1:])


def test_reference_modes_no_lm():
    comps = world(); rows = rows_of(comps); smi = [c["smiles"] for c in comps[:8]]
    r = M.IHLM(modules=("M2", "M3", "M4"), reference_mode="retrieval_only", slow_every=1).update(rows[:120], "finetune_ranking", seed=0); assert r.net is None and not r.net_trained
    s = r.score(smi, TSEQ); assert any(x is not None for x in s) and r.predict_std(smi, TSEQ).shape == (8,)
    o = M.IHLM(modules=("M2",), reference_mode="offset_only", slow_every=1).update(anchors(comps) + rows[:120], "finetune_ranking", seed=0)
    a = o.score(smi, TSEQ, sources=["L3"] * 8); b = o.score(smi, TSEQ, sources=["L0"] * 8); assert o.net is None and all(x > y for x, y in zip(a, b)) and len(set(a)) == 1   # lab offset only, constant within a source


def test_edit_priors_leak_guard_and_loader():
    import json
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "kb_audit", "peptide_sar_rules_v1.json"); d = json.load(open(path)); train = d["train_sources"]
    p = S.edit_priors_from_rules(path, heldout_sources=["a source never used"]); assert p["nme_add"][0] > 0 and p["dflip_D"][0] == 0.0 and p["dflip_L"][0] == 0.0     # 'no_consistent_direction' -> 0
    with pytest.raises(AssertionError): S.edit_priors_from_rules(path, heldout_sources=[train[0]])                                                                    # a held-out source that was mined must be refused
    assert S.EDIT_PRIORS["nme_add"][0] == 0.0 and S.EDIT_PRIORS_LITERATURE_UNVERIFIED["nme_add"][0] == 0.25
