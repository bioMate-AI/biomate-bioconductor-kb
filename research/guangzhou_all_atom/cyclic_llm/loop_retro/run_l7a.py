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

PARAMS = dict(n_init=100, rounds=10, batch=50, n_eval=800, steps0=100, steps_round=30)
V4_PARAMS = dict(n_init=50, rounds=5, batch=20, n_eval=150, steps0=60, steps_round=60)
ARMS = ("loop", "loop_kn", "random_fb", "shuffled", "frozen", "one_shot")
TOP = ("2020_Townsend", "2021_Kelly")


def ef5_auroc(score, hit):
    score = np.asarray(score, float); hit = np.asarray(hit, bool); n = len(score)
    k = max(1, int(round(0.05 * n))); top = np.argsort(-score, kind="stable")[:k]
    base = hit.mean(); ef = float(hit[top].mean() / base) if base > 0 else float("nan")
    npos, nneg = int(hit.sum()), int((~hit).sum())
    if npos == 0 or nneg == 0: return ef, float("nan")
    r = rankdata(score); auc = float((r[hit].sum() - npos * (npos + 1) / 2) / (npos * nneg)); return ef, auc


def make_eval_slice(pool, seed, n_eval):
    """E: seeded slice removed from the pool in ALL arms (paired). Returns (E list, pool without E)."""
    rng = random.Random(100000 + seed); E = sorted(rng.sample(list(pool), n_eval)); es = set(E)
    return E, [i for i in pool if i not in es]


class Ctx:
    """Everything an arm needs; built once per task."""
    def __init__(self, y, thr, thr_g, srcs, Kz, backend, p):
        self.y, self.thr, self.thr_g, self.srcs, self.Kz, self.B, self.p = y, thr, thr_g, srcs, Kz, backend, p


def _record(ctx, picks, rec, E, state):
    y = ctx.y
    rec["hits"].append(int(sum(y[i] >= ctx.thr for i in picks))); rec["hits_g"].append(int(sum(y[i] >= ctx.thr_g[i] for i in picks)))
    c = collections.Counter(ctx.srcs[i] for i in picks); rec["src"].append({TOP[0]: c.get(TOP[0], 0), TOP[1]: c.get(TOP[1], 0), "other": len(picks) - c.get(TOP[0], 0) - c.get(TOP[1], 0)})
    ef, auc = ef5_auroc(ctx.B.predict(state, E), y[E] >= ctx.thr); rec["ef5_E"].append(ef); rec["auroc_E"].append(auc)


def run_arm(ctx, arm, init, pool, E, seed, loop_revealed=None, state0=None):
    p, B, y = ctx.p, ctx.B, ctx.y; rng = np.random.default_rng(seed); rec = dict(hits=[], hits_g=[], src=[], ef5_E=[], auroc_E=[], revealed_final=None)
    ef, auc = ef5_auroc(B.predict(state0, E), y[E] >= ctx.thr); rec["ef5_E0"], rec["auroc_E0"] = ef, auc
    if arm == "one_shot":                                  # data- and compute-matched: ONE update on the loop's final revealed set, steps*rounds total
        st = B.fit(state0, loop_revealed, y[loop_revealed], p["steps_round"] * p["rounds"], seed + 1)
        ef, auc = ef5_auroc(B.predict(st, E), y[E] >= ctx.thr); rec["ef5_E"], rec["auroc_E"] = [ef], [auc]; rec["revealed_final"] = list(map(int, loop_revealed)); return rec
    labeled = list(init); ylab = list(y[init]); unl = list(pool); state = state0; frozen_rank = None   # ylab = labels AS THE MODEL SEES THEM (permuted per round in the shuffled arm)
    for r in range(p["rounds"]):
        U = np.array(unl)
        if arm == "random_fb": pick = [int(i) for i in rng.choice(U, p["batch"], replace=False)]
        elif arm == "frozen":
            if frozen_rank is None: frozen_rank = U[np.argsort(-B.predict(state0, U), kind="stable")]
            avail = set(unl); pick = [int(i) for i in frozen_rank if i in avail][:p["batch"]]
        else:
            s = B.predict(state, U)
            if arm == "loop_kn":
                w = 100.0 / (100.0 + len(labeled)); s = (1 - w) * K.zs(s) + w * K.zs(ctx.Kz[U])
            pick = [int(i) for i in U[np.argsort(-s, kind="stable")[:p["batch"]]]]
        sp = set(pick); unl = [i for i in unl if i not in sp]; labeled += pick
        if arm != "frozen":
            new = y[pick].copy()
            if arm == "shuffled": new = rng.permutation(new)
            ylab += list(new); state = B.fit(state, labeled, np.array(ylab), p["steps_round"], seed * 1000 + r)
        _record(ctx, pick, rec, E, state if arm != "frozen" else state0)
    rec["revealed_final"] = list(map(int, labeled)); return rec


def run_task(ctx, init, pool, E, seed):
    p, B, y = ctx.p, ctx.B, ctx.y; t0 = time.time()
    state0 = B.fit(B.init_state(), init, y[init], p["steps0"], seed)
    out = {"seed": seed, "n_pool": len(pool), "n_E": len(E), "E_hit_rate": float((y[E] >= ctx.thr).mean())}
    for arm in ARMS:
        if arm == "one_shot": continue
        out[arm] = run_arm(ctx, arm, init, pool, E, seed, state0=state0)
    out["one_shot"] = run_arm(ctx, "one_shot", init, pool, E, seed, loop_revealed=out["loop"]["revealed_final"], state0=state0)
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
    gz = lambda v: K.source_normalize(v, srcs); Kz = gz(gz(nme) - gz(hbd) - gz(tpsa))
    import loop_models as LM
    if backend == "gbm": B = LM.GBM(np.stack([r["x"] for r in recs]))
    elif backend == "atom_lm": B = LM.AtomLMReg(smiles, atom_ckpt, atom_vocab, device)
    elif backend == "chemberta": B = LM.ChemBERTaReg(smiles, device)
    elif backend == "v4": B = V4Backend(smiles, device)
    else: raise SystemExit("unknown backend")
    return recs, dict(y=y, thr=thr, thr_g=thr_g, srcs=srcs, scaf=scaf, flat=flat, Kz=Kz, B=B)


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
    ap.add_argument("--device", default="cpu"); ap.add_argument("--atom-ckpt"); ap.add_argument("--atom-vocab"); ap.add_argument("--v4-subset"); ap.add_argument("--smoke", action="store_true")
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    p = dict(V4_PARAMS if a.backend == "v4" else PARAMS)
    if a.smoke: p.update(rounds=2, steps0=10, steps_round=5, n_eval=min(p["n_eval"], 100), n_init=min(p["n_init"], 40), batch=min(p["batch"], 20))
    recs, d = build(a.csv, a.backend, a.device, a.atom_ckpt, a.atom_vocab, a.v4_subset if a.backend == "v4" else None)
    print("backend", a.backend, "n", len(recs), "thr", round(d["thr"], 3), "params", p, flush=True)
    for reg in a.regimes:
        for seed in parse_seeds(a.seeds):
            f = f"{a.out}/{a.backend}_{reg}_{seed}.json"
            if os.path.exists(f): continue
            init, pool = P.setup(reg, seed, d["srcs"], d["scaf"], p["n_init"], d["flat"])
            E, pool = make_eval_slice(pool, seed, p["n_eval"])
            assert not set(E) & set(pool) and not set(E) & set(init)
            ctx = Ctx(d["y"], d["thr"], d["thr_g"], d["srcs"], d["Kz"], d["B"], p)
            out = run_task(ctx, init, pool, E, seed); out.update(backend=a.backend, regime=reg, params=p)
            for arm in ARMS:
                if arm != "loop": out[arm].pop("revealed_final", None)
            tmp = f + ".tmp"; json.dump(out, open(tmp, "w")); os.replace(tmp, f)
            print("done", a.backend, reg, seed, {k: sum(out[k]["hits"]) for k in ARMS if out[k]["hits"]}, "EF5_E final loop/rand/shuf/frozen/oneshot:",
                  *[round(out[k]["ef5_E"][-1], 2) for k in ("loop", "random_fb", "shuffled", "frozen", "one_shot")], "s", out["seconds"], flush=True)


if __name__ == "__main__":
    main()
