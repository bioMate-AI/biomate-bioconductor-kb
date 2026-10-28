#!/usr/bin/env python3
"""L7a model-comparison replay of the closed loop (PREREG_LOOP.md amendment L7a). One task = (backend, regime, seed); written to OUTDIR/<backend>_<regime>_<seed>.json immediately; resumable.
usage: run_l7a.py CycPeptMPDB.csv OUTDIR --backend {gbm,atom_lm,chemberta,v4} [--regimes AB] [--seeds 0-9] [--device cuda] [--atom-ckpt P --atom-vocab P] [--smoke]
Arms per task: loop, loop_kn, random_fb, shuffled, frozen, one_shot. Metrics per round: hits (L5 definition), hits_g (within-group definition), pick source counts, EF5 and AUROC on the held-out slice E."""
import os, sys, json, random, argparse, collections, time
import numpy as np
os.environ.setdefault("FP_CHIRAL", "1"); os.environ.setdefault("LABEL_COL", "PAMPA")
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import run_loop as R, run_loop_par as P, run_loop_prior as K
from scipy.stats import rankdata

PARAMS = dict(n_init=100, rounds=10, batch=50, n_eval=800, steps0=100, steps_round=30, n_cand=150, n_flat_groups=60)
V4_PARAMS = dict(n_init=50, rounds=5, batch=20, n_eval=150, steps0=60, steps_round=60, n_cand=60, n_flat_groups=15)
ARMS = ("loop", "random_fb", "random_srcmatch", "shuffled", "frozen", "rule_kphys_sub", "loop_sub", "loop_kn_sub", "frozen_sub", "shuffled_sub", "noisy_sub", "loop_kn_contra_sub", "loop_kphys_sub", "loop_kphys_contra_sub", "loop_kshuf_sub", "one_shot")   # L7b: K_z arm dropped; *_sub = same per-round 150-candidate subsets as the large-LLM arms
ACTIVE = list(ARMS)          # set from --arms
NOCURVE = [False]
TOP = ("2020_Townsend", "2021_Kelly")


def ef5_auroc(score, hit):
    score = np.asarray(score, float); hit = np.asarray(hit, bool); n = len(score)
    k = max(1, int(round(0.05 * n))); top = np.argsort(-score, kind="stable")[:k]
    base = hit.mean(); ef = float(hit[top].mean() / base) if base > 0 else float("nan")
    npos, nneg = int(hit.sum()), int((~hit).sum())
    if npos == 0 or nneg == 0: return ef, float("nan")
    r = rankdata(score); auc = float((r[hit].sum() - npos * (npos + 1) / 2) / (npos * nneg)); return ef, auc


def subset(pool0, seed, r, revealed, n_cand=150):
    """Per-round seeded candidate subset, sampled from the ORIGINAL pool then stripped of revealed items: identical for every arm and for the large-LLM runner (paired)."""
    rr = random.Random(777 * seed + r); c = rr.sample(list(pool0), min(n_cand, len(pool0))); rv = set(revealed); return [i for i in c if i not in rv]


def make_flat_slice(pool, flat, seed, n_groups, y=None, min_members=3):
    """E_f (L7d): groups of stereoisomers (same flat structure) with >= 3 members in the pool and non-zero label variance; ONE seeded split per group: one REVEALED sibling, the rest TARGETS.
    Returns (targets, target_groups, siblings, pool_without_all): `target_groups[g]` = target indices of group g, `siblings[g]` = its revealed sibling. Everything is removed from the pool."""
    g = collections.defaultdict(list)
    for i in pool: g[flat[i]].append(i)
    keys = sorted(k for k, v in g.items() if len(v) >= min_members and (y is None or float(np.std(y[v])) > 0)); rng = random.Random(200000 + seed); sel = rng.sample(keys, min(n_groups, len(keys)))
    targets, tgroups, sibs = [], [], []
    for k in sel:
        mem = sorted(g[k]); s = rng.choice(mem); t_ = [m for m in mem if m != s]; sibs.append(s); tgroups.append(t_); targets += t_
    gone = set(targets) | set(sibs); return targets, tgroups, sibs, [i for i in pool if i not in gone]


def make_source_slice(pool, srcs, seed, max_per=40, frac=0.3, small=400):
    """E_s (L7d): for every source with < `small` peptides in the data, a seeded sample of min(max_per, frac of its pool members) from the pool; removed from the pool."""
    cnt = collections.Counter(srcs); by = collections.defaultdict(list)
    for i in pool: by[srcs[i]].append(i)
    rng = random.Random(300000 + seed); Es = []
    for s in sorted(by):
        if cnt[s] < small and len(by[s]) >= 15: Es += rng.sample(sorted(by[s]), min(max_per, max(10, int(frac * len(by[s])))))
    es = set(Es); return sorted(Es), [i for i in pool if i not in es]


def stereo_rho(score, groups_local, y):
    """Mean within-group Spearman(score, label) over target groups (L7d). A constant score inside a group counts as rho = 0 (ties), never as missing; groups with constant labels are not used.
    Returns (mean_rho, fraction_of_groups_with_non_constant_score)."""
    rs, nc = [], 0
    for ix in groups_local:
        s = np.asarray(score)[ix]; l = y[ix]
        if np.std(l) == 0: continue
        if np.std(s) > 0: nc += 1; rs.append(float(spearman(s, l)))
        else: rs.append(0.0)
    return (float(np.mean(rs)) if rs else float("nan")), (nc / len(rs) if rs else float("nan"))


def spearman(a, b):
    ra, rb = rankdata(a), rankdata(b); ra -= ra.mean(); rb -= rb.mean(); d = np.sqrt((ra ** 2).sum() * (rb ** 2).sum()); return float((ra * rb).sum() / d) if d > 0 else 0.0


def setup_L(seed, srcs, n_init, frac=0.25, min_n=20, max_labs=None):
    """Regime L (leave-labs-out, L7f): held-out labs = seeded labs with >= min_n peptides, never the two largest, drawn until ~frac of all peptides is held out. Returns (init, pool, heldout_peptides, heldout_sources);
    init and pool are TRAINING-source peptides only."""
    cnt = collections.Counter(srcs); giants = {s for s, _ in cnt.most_common(2)}; cand = sorted(s for s, c in cnt.items() if c >= min_n and s not in giants)
    rng = random.Random(500000 + seed); rng.shuffle(cand); held, tot = [], 0
    for s in cand:
        if tot >= frac * len(srcs) or (max_labs is not None and len(held) >= max_labs): break          # L9 sensitivity regime: at most max_labs=9 held-out labs
        held.append(s); tot += cnt[s]
    hs = set(held); train = [i for i in range(len(srcs)) if srcs[i] not in hs]; test = [i for i in range(len(srcs)) if srcs[i] in hs]
    ids = list(train); random.Random(seed).shuffle(ids); return ids[:n_init], ids[n_init:], test, sorted(held)


def make_eval_slice(pool, seed, n_eval):
    """E: seeded slice removed from the pool in ALL arms (paired). Returns (E list, pool without E)."""
    rng = random.Random(100000 + seed); E = sorted(rng.sample(list(pool), n_eval)); es = set(E)
    return E, [i for i in pool if i not in es]


class Ctx:
    """Everything an arm needs; built once per task."""
    def __init__(self, y, thr, thr_g, srcs, Kz, backend, p, Kn=None, Ef=None, Ef_groups=None, Ef_sib=None, Es=None, Kphys=None, Kshuf=None):
        self.y, self.thr, self.thr_g, self.srcs, self.Kz, self.B, self.p = y, thr, thr_g, srcs, Kz, backend, p
        self.Kn = Kn if Kn is not None else Kz; self.Ef, self.Ef_groups, self.Ef_sib, self.Es = Ef, Ef_groups, Ef_sib, Es
        self.Kphys = Kphys if Kphys is not None else self.Kn; self.Kshuf = Kshuf if Kshuf is not None else self.Kphys   # Kn = KB-equal knowledge signal (source-standardised N-methyl count)


def _stereo(ctx, state):
    """stereo_rho on the TARGET members only, zero-sibling setting. Returns the mean rho; the non-constant fraction is logged by the caller via _stereo_full when needed."""
    return _stereo_full(ctx, state)[0]


def _stereo_full(ctx, state):
    sc = ctx.B.predict(state, ctx.Ef); pos = {i: k for k, i in enumerate(ctx.Ef)}
    return stereo_rho(sc, [[pos[i] for i in g] for g in ctx.Ef_groups], ctx.y[ctx.Ef])


def _stereo_sar(ctx, state, labeled, ylab, seed):
    """SAR setting: ONE extra update (same steps as one loop round) on the final revealed set plus the revealed siblings' labels, then rank the targets."""
    assert len(labeled) == len(ylab), f"SAR update needs one label per revealed index (got {len(labeled)} indices, {len(ylab)} labels)"
    sib = list(ctx.Ef_sib); st = ctx.B.fit(state, list(labeled) + sib, np.array(list(ylab) + [ctx.y[i] for i in sib]), ctx.p["steps_round"], seed * 1000 + 999)
    return _stereo_full(ctx, st)


def _record(ctx, picks, rec, E, state):
    y = ctx.y
    rec["hits"].append(int(sum(y[i] >= ctx.thr for i in picks))); rec["hits_g"].append(int(sum(y[i] >= ctx.thr_g[i] for i in picks)))
    c = collections.Counter(ctx.srcs[i] for i in picks); rec["src"].append({TOP[0]: c.get(TOP[0], 0), TOP[1]: c.get(TOP[1], 0), "other": len(picks) - c.get(TOP[0], 0) - c.get(TOP[1], 0)})
    ef, auc = ef5_auroc(ctx.B.predict(state, E), y[E] >= ctx.thr); rec["ef5_E"].append(ef); rec["auroc_E"].append(auc)
    if ctx.Ef is not None: rec.setdefault("stereo_rho", []).append(_stereo(ctx, state))


def run_arm(ctx, arm, init, pool, E, seed, loop_revealed=None, state0=None):
    p, B, y = ctx.p, ctx.B, ctx.y; rng = np.random.default_rng(seed); t0 = time.time(); steps = 0
    rec = dict(hits=[], hits_g=[], src=[], ef5_E=[], auroc_E=[], revealed_final=None)
    ef, auc = ef5_auroc(B.predict(state0, E), y[E] >= ctx.thr); rec["ef5_E0"], rec["auroc_E0"] = ef, auc
    if ctx.Ef is not None: rec["stereo_rho0"] = _stereo(ctx, state0)
    if arm == "one_shot":                                  # data- and compute-matched: ONE update on the loop's final revealed set, steps*rounds total
        st = B.fit(state0, loop_revealed, y[loop_revealed], p["steps_round"] * p["rounds"], seed + 1)
        ef, auc = ef5_auroc(B.predict(st, E), y[E] >= ctx.thr); rec["ef5_E"], rec["auroc_E"] = [ef], [auc]; rec["revealed_final"] = list(map(int, loop_revealed))
        if ctx.Ef is not None:
            rec["stereo_rho"] = [_stereo(ctx, st)]; rec["stereo_rho_sar"], _ = _stereo_sar(ctx, st, loop_revealed, [y[i] for i in loop_revealed], seed)
        rec["fit_steps"], rec["seconds"] = p["steps_round"] * p["rounds"], round(time.time() - t0, 1); return rec
    base = arm[:-4] if arm.endswith("_sub") else arm; sub = arm.endswith("_sub") or arm == "rule_kphys_sub_inner"
    if base == "rule_kphys":                         # zero-learning rule: model-free; ctx.B is swapped for a scorer that returns K_phys so every metric (E, E_f, ...) is the RULE's ranking
        class _Rule:
            def __init__(s, K): s.K = K
            def init_state(s): return None
            def fit(s, st, idx, y, steps, seed): return None
            def predict(s, st, idx): return s.K[np.asarray(idx, dtype=int)]
        saved = ctx.B; ctx.B = _Rule(ctx.Kphys)
        try: return run_arm(ctx, "rule_kphys_sub_inner", init, pool, E, seed, state0=None)
        finally: ctx.B = saved
    if base == "rule_kphys_sub_inner": base = "loop_rule"
    labeled = list(init); ylab = list(y[init]); unl = list(pool); state = state0; frozen_rank = None   # ylab = labels AS THE MODEL SEES THEM (permuted per round in shuffled)
    revealed = list(init)                                                       # indices the MODEL has labels for (frozen arms: init only, their picks are never fed back); len(revealed) == len(ylab) always
    picked_all = list(init)                                                     # indices excluded from later candidate subsets
    rec.update(picks=[], pick_scores=[], pick_std=[]); has_std = hasattr(B, "predict_std")
    if sub: rec.update(cands=[], cand_scores=[])
    for r in range(p["rounds"]):
        if sub: U = np.array(subset(pool, seed, r, picked_all, p["n_cand"]), dtype=int)     # `pool` is the ORIGINAL pool (never shrunk for sub arms)
        else: U = np.array(unl)
        st_sel = state0 if base == "frozen" else state; s = None
        if base == "random_fb": pick = [int(i) for i in rng.choice(U, p["batch"], replace=False)]
        elif base == "random_srcmatch":                                         # L7m: random within source, with EXACTLY the loop's per-source counts of this round (shortfall filled at random)
            want = ctx.match_rounds[r] if getattr(ctx, "match_rounds", None) and r < len(ctx.match_rounds) else {}; pick = []; Uset = set(map(int, U))
            for s_, c_ in sorted(want.items()):
                cand_ = [i for i in map(int, U) if ctx.srcs[i] == s_ and i not in set(pick)]
                if cand_: pick += [int(i) for i in rng.choice(cand_, min(c_, len(cand_)), replace=False)]
            if len(pick) < p["batch"]:
                rest_ = [i for i in map(int, U) if i not in set(pick)]; pick += [int(i) for i in rng.choice(rest_, p["batch"] - len(pick), replace=False)]
        elif base == "frozen" and not sub:
            if frozen_rank is None: frozen_rank = U[np.argsort(-B.predict(state0, U), kind="stable")]
            avail = set(unl); pick = [int(i) for i in frozen_rank if i in avail][:p["batch"]]
        else:
            s = B.predict(st_sel, U)
            if base in ("loop_kn", "loop_kn_contra", "loop_kphys", "loop_kphys_contra", "loop_kshuf"):
                w = 100.0 / (100.0 + len(revealed))                    # fusion weight (L2/L5): w = n0/(n0+n), n0 = 100
                ch = {"loop_kn": ctx.Kn, "loop_kn_contra": -ctx.Kn, "loop_kphys": ctx.Kphys, "loop_kphys_contra": -ctx.Kphys, "loop_kshuf": ctx.Kshuf}[base]   # K_phys = textbook physchem (leak-free); contra = sign-flipped; kshuf = within-source-permuted (no information)
                s = (1 - w) * K.zs(s) + w * K.zs(ch[U])
            pick = [int(i) for i in U[np.argsort(-s, kind="stable")[:p["batch"]]]]
        rec["picks"].append(pick)
        if s is not None:
            pos = {int(i): k for k, i in enumerate(U)}; rec["pick_scores"].append([round(float(s[pos[i]]), 4) for i in pick])
            if has_std and base not in ("loop_kn", "loop_kn_contra", "loop_kphys", "loop_kphys_contra", "loop_kshuf"): sd = B.predict_std(st_sel, U); rec["pick_std"].append([round(float(sd[pos[i]]), 4) for i in pick])
        if sub: rec["cands"].append([int(i) for i in U]); rec["cand_scores"].append([round(float(v), 4) for v in s] if s is not None else None)
        sp = set(pick); unl = [i for i in unl if i not in sp]; picked_all += pick
        if base not in ("frozen", "loop_rule"):
            revealed += pick
            new = y[pick].copy()
            if base == "shuffled": new = rng.choice(y[np.array(pool)], len(pick), replace=False)        # L7d: global draw from the pool's label vector (no item- or batch-level association)
            if base == "noisy" and len(new) >= 5:                    # 20 % label corruption: those labels are permuted among themselves
                m = rng.choice(len(new), max(2, int(round(0.2 * len(new)))), replace=False); new[m] = rng.permutation(new[m])
            ylab += list(new); state = B.fit(state, revealed, np.array(ylab), p["steps_round"], seed * 1000 + r); steps += p["steps_round"]
        _record(ctx, pick, rec, E, state if base not in ("frozen",) else state0)
        if arm in ("loop", "loop_sub"):
            rec.setdefault("E_scores", []).append([round(float(v), 4) for v in B.predict(state, E)])
            if ctx.Es is not None: rec.setdefault("Es_scores", []).append([round(float(v), 4) for v in B.predict(state, ctx.Es)])
    fin = state if base != "frozen" else state0
    rec.setdefault("E_scores_final", [round(float(v), 4) for v in B.predict(fin, E)])
    if ctx.Ef is not None:
        rec["stereo_nonconst_frac"] = _stereo_full(ctx, fin)[1]; rec["stereo_rho_sar"], rec["stereo_sar_nonconst_frac"] = _stereo_sar(ctx, fin, revealed, ylab, seed)
    rec["revealed_final"] = list(map(int, revealed)); rec["picked_final"] = list(map(int, picked_all)); rec["fit_steps"], rec["seconds"] = steps, round(time.time() - t0, 1); return rec


def learning_curve(ctx, init, pool, E, seed, ks=(0, 25, 50, 100)):
    p, B, y = ctx.p, ctx.B, ctx.y; out = {}; U = np.array(subset(pool, seed, 0, init, p["n_cand"]), dtype=int)
    for k in ks:
        st = B.fit(B.init_state(), init[:k], y[init[:k]], int(round(p["steps0"] * k / 100.0)) if k > 0 else 0, seed)
        ef, auc = ef5_auroc(B.predict(st, E), y[E] >= ctx.thr); s = B.predict(st, U); pick = U[np.argsort(-s, kind="stable")[:p["batch"]]]
        out[str(k)] = dict(ef5_E=ef, auroc_E=auc, stereo_rho=_stereo(ctx, st) if ctx.Ef is not None else None, sub_hits=int(sum(y[i] >= ctx.thr for i in pick)), sub_hits_g=int(sum(y[i] >= ctx.thr_g[i] for i in pick)),
                           E_scores=[round(float(v), 4) for v in B.predict(st, E)], Es_scores=[round(float(v), 4) for v in B.predict(st, ctx.Es)] if ctx.Es is not None else None)
    return out


def run_task(ctx, init, pool, E, seed):
    p, B, y = ctx.p, ctx.B, ctx.y; t0 = time.time()
    state0 = B.fit(B.init_state(), init, y[init], p["steps0"], seed)
    out = {"seed": seed, "n_pool": len(pool), "n_E": len(E), "E_hit_rate": float((y[E] >= ctx.thr).mean()), "n_Ef": 0 if ctx.Ef is None else len(ctx.Ef), "init_fit_seconds": round(time.time() - t0, 1)}
    for arm in ACTIVE:
        if arm == "one_shot": continue
        if arm == "random_srcmatch":
            if "loop" not in out: continue                                       # needs the loop's picks of the same task
            ctx.match_rounds = [dict(collections.Counter(ctx.srcs[i] for i in rd)) for rd in out["loop"]["picks"]]
        out[arm] = run_arm(ctx, arm, init, pool, E, seed, state0=state0)
    if "one_shot" in ACTIVE and "loop" in out: out["one_shot"] = run_arm(ctx, "one_shot", init, pool, E, seed, loop_revealed=out["loop"]["revealed_final"], state0=state0)
    if not NOCURVE[0]: out["curve"] = learning_curve(ctx, init, pool, E, seed)                                    # L7c dimension 1: k = 0, 25, 50, 100 labels
    out["seconds"] = round(time.time() - t0, 1); return out


def build(csv_path, backend, device, atom_ckpt=None, atom_vocab=None, v4_subset=None):
    from rdkit import Chem
    from rdkit.Chem import rdMolDescriptors
    recs = R.load(csv_path); keep = list(range(len(recs)))
    if v4_subset is not None:
        ms = set(json.load(open(v4_subset))["mapped_smiles"]); keep = [i for i, r in enumerate(recs) if r["smiles"] in ms]; recs = [recs[i] for i in keep]
    srcs = [r["source"] for r in recs]; scaf = [r["scaf"] for r in recs]; flat = [r["flat"] for r in recs]; smiles = [r["smiles"] for r in recs]
    y = K.source_normalize(np.array([r["y"] for r in recs]), srcs); thr = float(np.quantile(y, 0.9))
    cnt = collections.Counter(srcs); grp = np.array([s if cnt[s] >= 20 else "__other__" for s in srcs]); thr_g = np.zeros(len(y))
    for g in set(grp.tolist()): m = grp == g; thr_g[m] = float(np.quantile(y[m], 0.9))
    M = [Chem.MolFromSmiles(s) for s in smiles]; NME = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])")
    nme = np.array([len(m.GetSubstructMatches(NME)) for m in M], float); hbd = np.array([rdMolDescriptors.CalcNumHBD(m) for m in M], float); tpsa = np.array([rdMolDescriptors.CalcTPSA(m) for m in M], float)
    gz = lambda v: K.source_normalize(v, srcs); Kz = gz(gz(nme) - gz(hbd) - gz(tpsa)); Kn = gz(nme)
    from rdkit.Chem import Descriptors, Crippen
    logp = np.array([Crippen.MolLogP(m) for m in M], float); hba = np.array([rdMolDescriptors.CalcNumHBA(m) for m in M], float)
    desc = np.stack([[Descriptors.MolWt(m), tpsa[i], hbd[i], hba[i], logp[i], rdMolDescriptors.CalcNumRotatableBonds(m), nme[i], max((len(r_) for r_ in m.GetRingInfo().AtomRings()), default=0),
                      m.GetNumHeavyAtoms(), rdMolDescriptors.CalcFractionCSP3(m)] for i, m in enumerate(M)]).astype(np.float32)
    descz = ((desc - desc.mean(0)) / np.where(desc.std(0) > 0, desc.std(0), 1.0)).astype(np.float32)             # z-scored over the data, no labels
    Kphys = (gz(-tpsa) + gz(-hbd) + gz(logp)) / 3.0                       # L7f: textbook physchem directions (Veber 2002; Over 2016; Rezai 2006), equal weights, source-standardised, NO label-mined parameter
    import loop_models as LM
    ln = backend.endswith("_ln"); backend_ = backend[:-3] if ln else backend
    base = backend_.replace("_phys", "") if backend_ not in ("gbm_physchem",) else backend_; phys = backend_.endswith("_phys")
    if backend.startswith("hf:"):                      # hf:<model_id>[:lora][:phys]  e.g. hf:DeepChem/ChemBERTa-77M-MLM:lora
        parts = backend.split(":"); mid = parts[1]; flags = set(parts[2:]); assert "trc" not in flags, "remote code is forbidden in this study (L7h)"; B = LM.HFReg(smiles, mid, device, descz if "phys" in flags else None, lora="lora" in flags, trust_remote_code=False); base = "hf"
        if "ln" in flags: B.peft = "ln"
    elif base == "knn": B = LM.KNN(np.stack([r["x"] for r in recs]))
    elif base == "gp": B = LM.GP(np.stack([r["x"] for r in recs]))
    elif base == "gbm": B = LM.GBM(np.stack([r["x"] for r in recs]))
    elif base == "gbm_physchem": B = LM.GBM(desc)
    elif base == "atom_lm":
        B = LM.AtomLMReg(smiles, atom_ckpt, atom_vocab, device, descz if phys else None)
        if ln: B.peft = "ln"
    elif base == "chemberta": B = LM.ChemBERTaReg(smiles, device, descz if phys else None)
    elif base == "v4": B = V4Backend(smiles, device)
    else: raise SystemExit("unknown backend")
    return recs, dict(y=y, thr=thr, thr_g=thr_g, srcs=srcs, scaf=scaf, flat=flat, Kz=Kz, Kn=Kn, Kphys=Kphys, B=B, desc=desc)


class V4Backend:
    """v4 through v4_eval/loop_model.LoopModel (scoring, tokens, converter) with PERMEABILITY conditioning (<p_hi>/<p_lo>, <e_na>) and the LoopModel pairwise ranking update.
    Only fully mapped SMILES are valid; the caller restricts the pool to them (run with --v4-subset)."""
    name = "v4"; DUMMY_TARGET = "A"
    def __init__(self, smiles, device="cpu"):
        sys.path.insert(0, os.path.join(HERE, "..", "v4_eval")); sys.path.insert(0, os.path.join(HERE, ".."))
        import torch, loop_model as L, smiles_to_monomers as S; self.torch, self.L = torch, L; self.dev = device
        ck = os.path.join(HERE, "..", "..", "runs_helm", "unified_cyclic_llm_v4.pt"); self.base = L.LoopModel.from_checkpoint(ck, device)
        self.tok = []
        for s in smiles:
            seg = S.segment(s, S.BASE); ok = seg.get("ok") and seg["complete"] and all(t in self.base.stoi for t in seg["tokens"]) and len(seg["tokens"]) + 4 <= self.base.block
            assert ok, "V4Backend received an unmapped SMILES"; self.tok.append(seg["tokens"])
        base_cls = L.LoopModel
        class Perm(base_cls):
            def _llr(s, token_lists, tf, grad=False):
                outs = []
                for pb in ("<p_hi>", "<p_lo>"):
                    ids = [[s.stoi["<e_na>"], s.stoi[pb], s.stoi[L.U.BOS]] + [s.stoi[m] for m in t] + [s.stoi[L.U.EOS]] for t in token_lists]
                    mx = max(len(x) for x in ids); X = torch.full((len(ids), mx), s.pad, dtype=torch.long)
                    for j, q in enumerate(ids): X[j, :len(q)] = torch.tensor(q)
                    TF = tf[None].repeat(len(ids), 1).to(s.dev); X = X.to(s.dev)
                    with torch.set_grad_enabled(grad):
                        lp = torch.log_softmax(s.model(X, TF), -1)[:, :mx]; tl = lp.gather(2, X[:, :, None])[:, :, 0]
                        outs.append(torch.stack([tl[j, 3:3 + len(t)].sum() for j, t in enumerate(token_lists)]))
                return outs[0] - outs[1]
        self.Perm = Perm; self.length = [len(t) for t in self.tok]
    def init_state(self):
        import copy
        return self.Perm(copy.deepcopy(self.base.model), self.base.toks, self.base.block, self.dev, self.base.dictionary)
    def fit(self, state, idx, y, steps, seed):
        import copy, torch
        idx = np.asarray(idx); y = np.asarray(y, float); new = self.Perm(copy.deepcopy(state.model), state.toks, state.block, self.dev, state.dictionary)
        if len(idx) < 2 or steps <= 0: return new
        rng = np.random.default_rng(seed); order = np.argsort(y)
        pairs = [(a, b) for ia, a in enumerate(idx) for ib, b in enumerate(idx) if y[ia] > y[ib]]
        if not pairs: return new
        torch.manual_seed(int(seed)); new.model.train(); opt = torch.optim.AdamW(new.model.parameters(), lr=3e-4, weight_decay=0.0); tf = new._tf_vec(self.DUMMY_TARGET)
        for _ in range(steps):
            sel = rng.choice(len(pairs), min(32, len(pairs)), replace=False); loss = 0.0
            for k in sel:
                w, l = pairs[k]; s = new._llr([self.tok[w], self.tok[l]], tf, grad=True); loss = loss - torch.nn.functional.logsigmoid(s[0] - s[1])
            loss = loss / len(sel); opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(new.model.parameters(), 1.0); opt.step()
        new.model.eval(); return new
    def predict(self, state, idx):
        return np.array(state.score_tokens([self.tok[i] for i in np.asarray(idx)], self.DUMMY_TARGET))


def parse_seeds(s):
    if "-" in s: a, b = s.split("-"); return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(",")]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("csv"); ap.add_argument("out"); ap.add_argument("--backend", required=True); ap.add_argument("--regimes", default="AB"); ap.add_argument("--seeds", default="0-9")
    ap.add_argument("--device", default="cpu"); ap.add_argument("--atom-ckpt"); ap.add_argument("--atom-vocab"); ap.add_argument("--v4-subset"); ap.add_argument("--smoke", action="store_true"); ap.add_argument("--arms", default=",".join(ARMS)); ap.add_argument("--no-curve", action="store_true"); ap.add_argument("--alias", default=""); ap.add_argument("--n-init", type=int, default=0)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True); global ACTIVE; ACTIVE = [x for x in ARMS if x in a.arms.split(",")]; NOCURVE[0] = a.no_curve
    p = dict(V4_PARAMS if a.backend == "v4" else PARAMS); alias = a.alias or a.backend.replace("/", "__").replace(":", "-")
    if a.n_init: p["steps0"] = int(round(p["steps0"] * a.n_init / p["n_init"])); p["n_init"] = a.n_init          # H4b few-label: steps0 scales with the initial set
    if a.smoke: p.update(rounds=2, steps0=10, steps_round=5, n_eval=min(p["n_eval"], 100), n_init=min(p["n_init"], 40), batch=min(p["batch"], 20))
    recs, d = build(a.csv, a.backend, a.device, a.atom_ckpt, a.atom_vocab, a.v4_subset if a.backend == "v4" else None)
    print("backend", a.backend, "n", len(recs), "thr", round(d["thr"], 3), "params", p, flush=True)
    for reg in a.regimes:
        for seed in parse_seeds(a.seeds):
            f = f"{a.out}/{alias}_{reg}_{seed}.json"
            if os.path.exists(f): continue
            if reg in ("L", "M"):                                             # leave-labs-out; M = L9 (L7k addendum 2): at most 9 held-out labs: loop pool = training labs; E/E_s/E_f from held-out labs only
                init, pool, test, held = setup_L(seed, d["srcs"], p["n_init"], max_labs=(9 if reg == "M" else None)); E, rest = make_eval_slice(test, seed, p["n_eval"]); Ef, Efg, Efs, rest = make_flat_slice(rest, d["flat"], seed, p["n_flat_groups"], d["y"]); Es, rest = make_source_slice(rest, d["srcs"], seed)
                assert all(d["srcs"][i] in set(held) for i in E + Ef + Efs + Es) and all(d["srcs"][i] not in set(held) for i in list(pool) + list(init)), "regime L leakage between training and held-out labs"
            else:
                init, pool = P.setup(reg, seed, d["srcs"], d["scaf"], p["n_init"], d["flat"])
                E, pool = make_eval_slice(pool, seed, p["n_eval"]); Ef, Efg, Efs, pool = make_flat_slice(pool, d["flat"], seed, p["n_flat_groups"], d["y"]); Es, pool = make_source_slice(pool, d["srcs"], seed)
            allx = [set(E), set(Ef), set(Efs), set(Es)]; assert all(not a & b for k, a in enumerate(allx) for b in allx[k + 1:]) and all(not a & set(pool) and not a & set(init) for a in allx)
            Kshuf = d["Kphys"].copy(); rr = np.random.default_rng(seed + 7)
            for s_ in sorted(set(d["srcs"])): ix = np.array([i for i, v in enumerate(d["srcs"]) if v == s_]); Kshuf[ix] = d["Kphys"][rr.permutation(ix)]      # permuted within source: same distribution, no information
            ctx = Ctx(d["y"], d["thr"], d["thr_g"], d["srcs"], d["Kz"], d["B"], p, d["Kn"], Ef, Efg, Efs, Es, d["Kphys"], Kshuf)
            out = run_task(ctx, init, pool, E, seed); out.update(backend=alias, backend_spec=a.backend, regime=reg, params=p, cost_info=(d["B"].cost_info() if hasattr(d["B"], "cost_info") else None), E=[int(i) for i in E], Es=[int(i) for i in Es], Ef_groups=[[int(i) for i in g] for g in Efg], Ef_sib=[int(i) for i in Efs], init=[int(i) for i in init])
            for arm in ARMS:
                if arm in out and arm != "loop": out[arm].pop("revealed_final", None)
            tmp = f + ".tmp"; json.dump(out, open(tmp, "w")); os.replace(tmp, f)
            print("done", a.backend, reg, seed, {k: sum(out[k]["hits"]) for k in ACTIVE if k in out and out[k].get("hits")}, "s", out["seconds"], flush=True)


if __name__ == "__main__":
    main()
