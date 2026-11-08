"""DEV measurement of the knowledge levels L0-L3 with ChemFM-1B under the hard-rule mask (GPU/CPU spot only). A development check of the wiring, NOT evidence of benefit:
no held-out verifier, no baseline comparison, TRAIN verifiers only (phys_potential: unfitted textbook potential; perm_A_hgb: fitted on group A = Townsend + Kelly), small B.
usage: dev_measure.py OUT --levels L0,L1,L2,L3 --seeds 0,1,2,3,4 --n 150 --frac 0.5 [--lam 0.5] [--batch 32]
Same prefix protocol as pilot 3 / masked_sampling.py (seeded completion of CycPeptMPDB-dev seeds; the sampler is masked_sampling.sample_group, whose soft-logit hook applies the level's
potential); per (level, seed) result file, resumable. Verifier scale: z-score against 1,500 rule-satisfying library draws (seed 20261029), the generation space of amendment A4.
Reported per (level, seed): completion, validity, rule satisfaction (RDKit, completed rows), N-Me / D-residue (stereo-SMARTS proxy) / ring-size (largest ring atoms/3) distributions,
uniqueness, internal diversity, train-verifier z means among rule-satisfying unique molecules; the summary gives mean and 95% t-interval over seeds."""
import argparse
import collections
import gzip
import json
import os
import random
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.normpath(os.path.join(HERE, ".."))
CL = os.path.normpath(os.path.join(AP, ".."))
for p in (AP, os.path.join(AP, "rules"), os.path.join(CL, "generation_pilot"), CL, os.path.join(AP, "track_e")):
    sys.path.insert(0, p)
import torch  # noqa: E402
from rdkit import Chem, DataStructs, RDLogger  # noqa: E402
from rdkit.Chem import AllChem  # noqa: E402

RDLogger.DisableLog("rdApp.*")
import gen_pilot  # noqa: E402
import masked_sampling as MS  # noqa: E402
from rules import spec, vocab as V  # noqa: E402
from knowledge_augment import levels as L  # noqa: E402

NME = Chem.MolFromSmarts("[CX3](=O)[NX3;!H1]([CH3])")
D_RES = Chem.MolFromSmarts("[NX3][C@H]([#6])C(=O)")        # D-alpha-carbon proxy (L is [C@@H] in this atom order)
L_RES = Chem.MolFromSmarts("[NX3][C@@H]([#6])C(=O)")


def stats_of(smiles):
    m = Chem.MolFromSmiles(smiles)
    rr = [len(r) for r in m.GetRingInfo().AtomRings()]
    return dict(nme=len(m.GetSubstructMatches(NME)), d=len(m.GetSubstructMatches(D_RES)), l=len(m.GetSubstructMatches(L_RES)),
                ring_res=int(max(4, min(30, round(max(rr) / 3.0)))) if rr else 0)


def build_train_verifiers(ann_path=None, gen_ref_n=1500):
    """phys_potential + perm_A_hgb (group A only), z-scored against rule-satisfying library draws. Held-out/stop models are NOT built."""
    import verifiers_e as VE
    import baselines as BL
    from sklearn.ensemble import HistGradientBoostingRegressor
    d = VE.load_labelled(ann_path) if ann_path else VE.load_labelled()
    A = set(L_groups_A())
    d = d[d["Source"].isin(A)]
    assert set(d["Source"].unique()) <= A
    mA = HistGradientBoostingRegressor(max_iter=300, learning_rate=0.06, random_state=0).fit(VE.features(d["smiles"].tolist(), "A"), d["z"].values)

    def raw_phys(s):
        tpsa, hbd, _, logp, _, rot, _ = [float(x) for x in VE.desc7(Chem.MolFromSmiles(s))]
        return -0.01 * tpsa - 0.15 * hbd + 0.20 * logp - 0.10 * max(0.0, rot - 10.0)

    raws = {"phys_potential": raw_phys, "perm_A_hgb": lambda s: float(mA.predict(VE.features([s], "A"))[0])}
    rr, ref = random.Random(20261029), []
    while len(ref) < gen_ref_n:
        for s in BL.GP.gen_lib([], 200, rr, rr.choice(BL.LIB_CFGS)):
            c = VE.canon(s)
            if c and BL.constraint(c):
                ref.append(c)
    ref = ref[:gen_ref_n]
    mom = {k: (lambda v: (float(np.mean(v)), float(np.std(v)) + 1e-9))([f(s) for s in ref]) for k, f in raws.items()}
    return {k: (lambda s, _f=f, _m=mom[k]: (_f(s) - _m[0]) / _m[1]) for k, f in raws.items()}, dict(n_group_a=len(d), gen_ref_n=len(ref), moments=mom, sources=sorted(A))


def L_groups_A():
    g = json.load(open(L.P["groups"]))["membership"]
    return sorted(s for s, v in g.items() if v["group"] == "A")


def diversity(smis, cap=300, seed=0):
    smis = sorted(set(smis))
    if len(smis) < 2:
        return None
    rng = random.Random(seed)
    smis = rng.sample(smis, min(cap, len(smis)))
    fps = [AllChem.GetMorganFingerprintAsBitVect(Chem.MolFromSmiles(s), 2, 2048) for s in smis]
    sims = [DataStructs.BulkTanimotoSimilarity(fps[i], fps[i + 1:]) for i in range(len(fps) - 1)]
    return float(1 - np.mean(np.concatenate(sims)))


def run_cell(level, seed, args, ctx, tok, model, dev, voc, verifiers):
    fn = os.path.join(args.out, "cell_%s_s%d.json" % (level, seed))
    if os.path.exists(fn):
        return json.load(open(fn))
    lv = L.build_level(level, lam_soft=args.lam)
    con = lv.constraint(voc, max_len=MS.MAXLEN)
    rng = random.Random(seed * 7919 + 13)
    gen = np.random.default_rng(seed)
    torch.manual_seed(seed)
    groups = MS.prompts_for(tok, ctx["S"], args.n, args.frac, rng)
    raw, stats, reasons, t0 = [""] * args.n, {"mask_seconds": 0.0, "row_steps": 0}, collections.Counter(), time.time()
    for P, items in sorted(groups.items()):
        for k in range(0, len(items), args.batch):
            r = MS.sample_group(model, dev, con, items[k:k + args.batch], args.temp, True, gen, stats)
            for row, (gids, fin, lz, prompt, why) in r.items():
                reasons[why] += 1
                if fin:
                    raw[row] = voc.decode(list(prompt) + gids)
    comp = [s for s in raw if s]
    valid = [s for s in comp if Chem.MolFromSmiles(s) is not None]
    sat = [s for s in valid if spec.satisfies_smiles(s)]
    uniq = sorted(set(sat))
    st = [stats_of(s) for s in sat]
    zs = {k: [f(s) for s in uniq] for k, f in verifiers.items()}
    pct = lambda a, q: float(np.percentile(a, q)) if len(a) else None  # noqa: E731
    out = dict(level=level, seed=seed, config_hash=lv.config_hash, lam=lv.lam_soft, n=args.n, frac=args.frac, completion=len(comp) / args.n, validity=len(valid) / args.n,
               rule_satisfaction_of_completed=(len(sat) / len(comp)) if comp else None, n_sat=len(sat), n_unique_sat=len(uniq), diversity=diversity(uniq, seed=seed),
               nme_mean=float(np.mean([x["nme"] for x in st])) if st else None, nme_hist=dict(collections.Counter(x["nme"] for x in st)),
               d_res_mean=float(np.mean([x["d"] for x in st])) if st else None, d_res_hist=dict(collections.Counter(x["d"] for x in st)),
               ring_res_mean=float(np.mean([x["ring_res"] for x in st])) if st else None, ring_res_hist=dict(collections.Counter(x["ring_res"] for x in st)),
               z={k: dict(mean=float(np.mean(v)) if v else None, sd=float(np.std(v)) if v else None, q10=pct(v, 10), q50=pct(v, 50), q90=pct(v, 90),
                          top10_mean=float(np.mean(sorted(v)[-10:])) if v else None) for k, v in zs.items()},
               row_outcomes=dict(reasons), seconds=round(time.time() - t0, 1), device=dev)
    os.makedirs(args.out, exist_ok=True)
    with gzip.open(os.path.join(args.out, "raw_%s_s%d.smi.gz" % (level, seed)), "wt") as f:
        f.write("\n".join(raw))
    json.dump(out, open(fn, "w"), indent=1)
    print(json.dumps({k: out[k] for k in ("level", "seed", "completion", "validity", "rule_satisfaction_of_completed", "n_unique_sat", "nme_mean", "ring_res_mean", "seconds")}), flush=True)
    return out


def summarise(cells, levels):
    from scipy import stats as sps
    metrics = ["completion", "validity", "rule_satisfaction_of_completed", "diversity", "nme_mean", "d_res_mean", "ring_res_mean", "n_unique_sat"]
    ci = lambda v: (float(np.mean(v)), float(sps.t.ppf(0.975, len(v) - 1) * np.std(v, ddof=1) / np.sqrt(len(v))) if len(v) > 1 else None)  # noqa: E731
    rows = {}
    for lv in levels:
        cs = [c for c in cells if c["level"] == lv]
        r = {m: ci([c[m] for c in cs if c[m] is not None]) for m in metrics}
        for vn in cs[0]["z"]:
            for stat in ("mean", "top10_mean"):
                r["z_%s_%s" % (vn, stat)] = ci([c["z"][vn][stat] for c in cs if c["z"][vn][stat] is not None])
        r["n_seeds"] = len(cs)
        r["config_hash"] = cs[0]["config_hash"]
        rows[lv] = r
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--levels", default="L0,L1,L2,L3")
    ap.add_argument("--seeds", default="0,1,2,3,4")
    ap.add_argument("--n", type=int, default=150)
    ap.add_argument("--frac", type=float, default=0.5)
    ap.add_argument("--temp", type=float, default=1.0)
    ap.add_argument("--lam", type=float, default=L.DEFAULT_LAM)
    ap.add_argument("--batch", type=int, default=32)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    assert L.leak_report()["ok"]
    ctx = gen_pilot.context()
    tok, model, dev = MS.load_model(os.environ["CHEMFM_DIR"])
    voc = V.load(os.path.join(os.environ["CHEMFM_DIR"], "tokenizer.json"))
    verifiers, vinfo = build_train_verifiers()
    json.dump(dict(vinfo, verifier_roles="train only", args=vars(args), leak_report=L.leak_report()), open(os.path.join(args.out, "setup.json"), "w"), indent=1, default=str)
    levels, seeds = args.levels.split(","), [int(x) for x in args.seeds.split(",")]
    cells = [run_cell(lv, s, args, ctx, tok, model, dev, voc, verifiers) for s in seeds for lv in levels]
    json.dump(summarise(cells, levels), open(os.path.join(args.out, "summary.json"), "w"), indent=1)
    print("SUMMARY DONE", flush=True)


if __name__ == "__main__":
    main()
