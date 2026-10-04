#!/usr/bin/env python3
"""Track A2 + A3 — principled multi-objective selection (qNEHVI) over the existing
candidate pools, compared to the hand-tuned composite that produced the panels.

Objectives (all MAXIMIZED):
  1. binding      = A1 real-data model pAffinity (pKd-like)   [replaces the MM-GBSA/iPTM proxy]
  2. permeability = ECFP4 regressor on CycPeptMPDB (log Papp) [prior perm model, ranking-grade]
  3. synthesizability = -SA_score (RDKit contrib)             [lower SA = easier synthesis]
  (selectivity: NOT derivable from current single-target data -> omitted, documented.)

We compare, in this objective space, the dominated HYPERVOLUME of:
  - COMPOSITE top-k : the panel the existing hand-tuned composite selected
  - qNEHVI   top-k : BoTorch qNEHVI batch selection (GP surrogate on descriptors)
  - GREEDY-HV top-k: exact greedy hypervolume-contribution selection
                     (= the principled optimum when objectives are known/noiseless;
                      qNEHVI converges to this in the perfect-model limit)

A3: report how the qNEHVI / greedy-HV top-N differ from the composite panel.
"""
import argparse, json, os, sys, pickle, warnings
import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import rdFingerprintGenerator

warnings.filterwarnings("ignore")
RDLogger.DisableLog("rdApp.*")

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")
sys.path.insert(0, HERE)
from binding_features import featurize_smiles, DESC_NAMES

# SA scorer (RDKit contrib)
from rdkit.Chem import RDConfig
sys.path.append(os.path.join(RDConfig.RDContribDir, "SA_Score"))
import sascorer  # noqa

_FP = rdFingerprintGenerator.GetMorganGenerator(radius=2, fpSize=2048)
_ACID = Chem.MolFromSmarts("[CX3](=O)[OX2H1]")
_AMINE = Chem.MolFromSmarts("[NX3;H2;!$([NX3][CX3]=[OX1])]")


def cyclize(mol):
    a = mol.GetSubstructMatches(_ACID); n = mol.GetSubstructMatches(_AMINE)
    if not a or not n:
        return None
    c_atom, oh_atom = a[-1][0], a[-1][1]; n_atom = n[0][0]
    rw = Chem.RWMol(mol); rw.AddBond(n_atom, c_atom, Chem.BondType.SINGLE); rw.RemoveAtom(oh_atom)
    m = rw.GetMol()
    try:
        Chem.SanitizeMol(m)
    except Exception:
        return None
    return m


def seq_to_cyclic_smiles(seq):
    m = Chem.MolFromSequence(seq)
    if m is None:
        return None, None
    mc = cyclize(m)
    if mc is None:
        return Chem.MolToSmiles(m), "linear_fallback"
    return Chem.MolToSmiles(mc), "cyclic"


# ---------------- permeability model (CycPeptMPDB ECFP4 regressor) ----------------
def train_perm(csv_path, n=5, seed=0):
    import csv
    from sklearn.ensemble import HistGradientBoostingRegressor
    X, y = [], []
    for r in csv.DictReader(open(csv_path)):
        try:
            p = float(r.get("Permeability", ""))
        except (TypeError, ValueError):
            continue
        if not (-10.5 < p < -3.5):
            continue
        m = Chem.MolFromSmiles((r.get("SMILES", "") or "").strip())
        if m is None:
            continue
        X.append(np.asarray(_FP.GetFingerprint(m), dtype=np.float32)); y.append(p)
    X, y = np.array(X), np.array(y)
    rng = np.random.default_rng(seed); models = []
    for s in range(n):
        idx = rng.integers(0, len(y), len(y))
        mdl = HistGradientBoostingRegressor(max_iter=300, learning_rate=0.05,
                                            max_leaf_nodes=31, l2_regularization=1.0, random_state=s)
        mdl.fit(X[idx], y[idx]); models.append(mdl)
    def predict(F):
        return np.vstack([m.predict(F) for m in models]).mean(0)
    return predict, len(y)


# ---------------- binding model (A1 production) ----------------
ASSAY_TYPES = ["IC50", "Ki", "EC50", "Kd"]


def load_binding():
    with open(os.path.join(RESULTS, "binding_model_prod.pkl"), "rb") as fh:
        d = pickle.load(fh)
    model = d["model"]
    def predict(smiles_list):
        feats, keep = [], []
        for i, smi in enumerate(smiles_list):
            r = featurize_smiles(smi)
            if r is None:
                feats.append(None)
            else:
                fp, de = r
                oh = np.zeros(len(ASSAY_TYPES), np.float32); oh[ASSAY_TYPES.index("Kd")] = 1.0
                feats.append(np.hstack([fp.astype(np.float32), de.astype(np.float32), oh])); keep.append(i)
        out = np.full(len(smiles_list), np.nan)
        if keep:
            X = np.vstack([feats[i] for i in keep])
            X = np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)
            out[keep] = model.predict(X)
        return out
    return predict


# ---------------- hypervolume (fast numpy, maximization, ref assumed <= all points) ----------------
def _hv2d(pts):
    """2D dominated area wrt origin (maximization). pts: (n,2) >=0."""
    if len(pts) == 0:
        return 0.0
    order = np.argsort(-pts[:, 0])  # x descending
    area = 0.0; y_prev = 0.0
    for i in order:
        x, y = pts[i, 0], pts[i, 1]
        if y > y_prev:
            area += x * (y - y_prev); y_prev = y
    return area


def _hv3d(pts):
    """3D dominated volume wrt origin (maximization). pts: (n,3) >=0."""
    if len(pts) == 0:
        return 0.0
    order = np.argsort(-pts[:, 2])  # z descending
    z = pts[order, 2]; xy = pts[order, :2]
    vol = 0.0
    for k in range(len(order)):
        z_next = z[k + 1] if k + 1 < len(order) else 0.0
        h = z[k] - z_next
        if h <= 0:
            continue
        vol += _hv2d(xy[:k + 1]) * h
    return vol


def hv(Y, ref):
    """dominated hypervolume of maximization objectives Y (n x m) wrt ref (m,).
    Objectives are pre-normalized to >=0 with ref=0; supports m in {2,3}."""
    Y = np.asarray(Y, dtype=np.float64)
    ref = np.asarray(ref, dtype=np.float64)
    P = Y - ref
    P = P[np.all(P > 0, axis=1)]  # points must dominate ref in all dims
    if len(P) == 0:
        return 0.0
    if P.shape[1] == 2:
        return _hv2d(P)
    if P.shape[1] == 3:
        return _hv3d(P)
    raise ValueError("hv() supports 2 or 3 objectives")


def greedy_hv_select(Y, k, ref):
    """exact greedy max-hypervolume-contribution subset selection."""
    chosen, remaining = [], list(range(len(Y)))
    for _ in range(min(k, len(Y))):
        best, best_hv = None, -1.0
        base = Y[chosen] if chosen else np.zeros((0, Y.shape[1]))
        for j in remaining:
            cand = np.vstack([base, Y[j]])
            h = hv(cand, ref)
            if h > best_hv:
                best_hv, best = h, j
        chosen.append(best); remaining.remove(best)
    return chosen


def qnehvi_select(Xdesc, Y, k, ref, n_init=6, seed=0):
    """BoTorch qNEHVI batch selection over the discrete pool.
    GP surrogate maps design descriptors -> objectives; acquisition chosen over remaining pool."""
    import torch
    from botorch.models import SingleTaskGP
    from botorch.models.model_list_gp_regression import ModelListGP
    from botorch.models.transforms.outcome import Standardize
    from botorch.fit import fit_gpytorch_mll
    from gpytorch.mlls import SumMarginalLogLikelihood
    from botorch.acquisition.multi_objective.logei import qLogNoisyExpectedHypervolumeImprovement
    from botorch.sampling.normal import SobolQMCNormalSampler
    from botorch.utils.transforms import normalize

    torch.manual_seed(seed)
    torch.set_num_threads(max(1, os.cpu_count() or 1))
    dev = torch.double
    X = torch.tensor(Xdesc, dtype=dev)
    bounds = torch.stack([X.min(0).values, X.max(0).values])
    span = (bounds[1] - bounds[0]).clamp_min(1e-9); bounds[1] = bounds[0] + span
    Xn = normalize(X, bounds)
    Yt = torch.tensor(Y, dtype=dev)
    ref_t = torch.tensor(ref, dtype=dev)

    rng = np.random.default_rng(seed)
    chosen = list(int(c) for c in rng.choice(len(Y), size=min(n_init, len(Y)), replace=False))
    sampler = SobolQMCNormalSampler(sample_shape=torch.Size([16]))
    while len(chosen) < k and len(chosen) < len(Y):
        idx = torch.tensor(chosen)
        models = [SingleTaskGP(Xn[idx], Yt[idx, i:i+1], outcome_transform=Standardize(m=1))
                  for i in range(Y.shape[1])]
        model = ModelListGP(*models)
        mll = SumMarginalLogLikelihood(model.likelihood, model)
        try:
            fit_gpytorch_mll(mll)
        except Exception:
            pass
        acq = qLogNoisyExpectedHypervolumeImprovement(
            model=model, ref_point=ref_t, X_baseline=Xn[idx],
            sampler=sampler, prune_baseline=True, cache_root=False)
        remaining = [j for j in range(len(Y)) if j not in chosen]
        with torch.no_grad():
            vals = acq(Xn[torch.tensor(remaining)].unsqueeze(1))
        pick = remaining[int(torch.argmax(vals))]
        chosen.append(int(pick))
        print(f"    qNEHVI picked {len(chosen)}/{k}", flush=True)
    return chosen[:k]


def normalize_obj(Y):
    """min-max to [0,1] per column for HV (ref point = 0)."""
    lo = Y.min(0); hi = Y.max(0); span = np.where(hi - lo > 1e-9, hi - lo, 1.0)
    return (Y - lo) / span, lo, span


def process_pool(name, seqs, composite_order, perm_pred, bind_pred, k, args):
    smis, modes = [], []
    for s in seqs:
        sm, mode = seq_to_cyclic_smiles(s)
        smis.append(sm); modes.append(mode)
    # objectives
    binding = bind_pred(smis)  # pAff, maximize
    fps = []
    for sm in smis:
        m = Chem.MolFromSmiles(sm) if sm else None
        fps.append(np.asarray(_FP.GetFingerprint(m), dtype=np.float32) if m else np.zeros(2048, np.float32))
    perm = perm_pred(np.vstack(fps))  # logPapp, maximize
    sa = []
    for sm in smis:
        m = Chem.MolFromSmiles(sm) if sm else None
        sa.append(sascorer.calculateScore(m) if m else 10.0)
    synth = -np.array(sa)  # maximize (-SA)

    valid = ~np.isnan(binding)
    Yraw = np.vstack([binding, perm, synth]).T
    # replace nan binding with column min so they rank last
    for c in range(Yraw.shape[1]):
        col = Yraw[:, c]; col[np.isnan(col)] = np.nanmin(col); Yraw[:, c] = col
    Ynorm, lo, span = normalize_obj(Yraw)
    ref = np.zeros(Yraw.shape[1])

    # descriptors for GP = normalized objective-adjacent physchem (MW, LogP, TPSA, HBD) + len
    desc = []
    for sm in smis:
        r = featurize_smiles(sm) if sm else None
        desc.append(r[1][:5] if r else np.zeros(5, np.float32))
    Xdesc = np.vstack(desc).astype(np.float64)
    Xdesc = np.nan_to_num(Xdesc, nan=0.0, posinf=0.0, neginf=0.0)

    comp_topk = list(composite_order[:k])
    greedy_topk = greedy_hv_select(Ynorm, k, ref)

    # persist objective arrays so the qNEHVI (torch) phase runs in a SEPARATE process
    # (torch's libomp + XGBoost's libomp cannot coexist in one process on macOS -> OMP Error #179)
    np.savez_compressed(os.path.join(RESULTS, f"pool_obj_{name}.npz"),
                        Ynorm=Ynorm, Xdesc=Xdesc, Yraw=Yraw,
                        comp_topk=np.array(comp_topk), greedy_topk=np.array(greedy_topk),
                        seqs=np.array(seqs, dtype=object), modes=np.array(modes, dtype=object), k=k)

    hv_comp = hv(Ynorm[comp_topk], ref)
    hv_greedy = hv(Ynorm[greedy_topk], ref)
    hv_full = hv(Ynorm, ref)

    def summ(idxs):
        return [{"rank": r + 1, "seq": seqs[i], "pAff": round(float(Yraw[i, 0]), 3),
                 "logPapp": round(float(Yraw[i, 1]), 3), "SA": round(float(-Yraw[i, 2]), 2),
                 "mode": modes[i]} for r, i in enumerate(idxs)]

    overlap_g = len(set(comp_topk) & set(greedy_topk))

    return {
        "pool_size": len(seqs), "k": k, "n_valid_binding": int(valid.sum()),
        "cyclization_modes": {m: int(modes.count(m)) for m in set(modes)},
        "hypervolume": {"composite_topk": round(hv_comp, 5),
                        "qnehvi_topk": None,
                        "greedy_hv_topk": round(hv_greedy, 5),
                        "full_pool": round(hv_full, 5),
                        "qnehvi_gain_vs_composite_pct": None,
                        "greedy_gain_vs_composite_pct": round(100 * (hv_greedy - hv_comp) / max(hv_comp, 1e-9), 1)},
        "topk_overlap_with_composite": {"qnehvi": None, "greedy_hv": overlap_g, "of_k": k},
        "composite_topk": summ(comp_topk),
        "qnehvi_topk": None,
        "greedy_hv_topk": summ(greedy_topk),
        "objective_ranges": {"pAff": [round(float(Yraw[:,0].min()),2), round(float(Yraw[:,0].max()),2)],
                             "logPapp": [round(float(Yraw[:,1].min()),2), round(float(Yraw[:,1].max()),2)],
                             "SA": [round(float((-Yraw[:,2]).min()),2), round(float((-Yraw[:,2]).max()),2)]},
    }


def run_qnehvi_phase(report_path):
    """Phase 2 (torch only): load each pool_obj_*.npz, run BoTorch qNEHVI, patch the report."""
    report = json.load(open(report_path))
    for name, pool in report["pools"].items():
        npz = os.path.join(RESULTS, f"pool_obj_{name}.npz")
        if not os.path.exists(npz):
            print(f"  [no npz for {name}; skip]"); continue
        z = np.load(npz, allow_pickle=True)
        Ynorm = z["Ynorm"]; Xdesc = z["Xdesc"]; Yraw = z["Yraw"]
        seqs = list(z["seqs"]); modes = list(z["modes"]); k = int(z["k"])
        comp_topk = list(int(i) for i in z["comp_topk"])
        ref = np.zeros(Ynorm.shape[1])
        print(f"== qNEHVI for {name} (n={len(seqs)}, k={k}) ==", flush=True)
        try:
            qnehvi_topk = qnehvi_select(Xdesc, Ynorm, k, ref)
        except Exception as e:
            print(f"  [qNEHVI failed for {name}: {e}]"); continue
        hv_q = hv(Ynorm[qnehvi_topk], ref)
        hv_comp = pool["hypervolume"]["composite_topk"]
        pool["hypervolume"]["qnehvi_topk"] = round(hv_q, 5)
        pool["hypervolume"]["qnehvi_gain_vs_composite_pct"] = round(100 * (hv_q - hv_comp) / max(hv_comp, 1e-9), 1)
        pool["topk_overlap_with_composite"]["qnehvi"] = len(set(comp_topk) & set(qnehvi_topk))
        pool["qnehvi_topk"] = [{"rank": r + 1, "seq": seqs[i], "pAff": round(float(Yraw[i, 0]), 3),
                               "logPapp": round(float(Yraw[i, 1]), 3), "SA": round(float(-Yraw[i, 2]), 2),
                               "mode": modes[i]} for r, i in enumerate(qnehvi_topk)]
        h = pool["hypervolume"]
        print(f"  HV composite={h['composite_topk']} qNEHVI={h['qnehvi_topk']} greedy={h['greedy_hv_topk']} "
              f"(qNEHVI {h['qnehvi_gain_vs_composite_pct']:+}%)", flush=True)
    json.dump(report, open(report_path, "w"), indent=2)
    print(f"patched {report_path}", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=10)
    ap.add_argument("--perm-csv", default=os.path.join(HERE, "data/raw/CycPeptMPDB_Peptide_All.csv"))
    ap.add_argument("--phase", choices=["objectives", "qnehvi"], default="objectives",
                    help="objectives: compute objectives + composite/greedy-HV (no torch). "
                         "qnehvi: load saved objectives + run BoTorch qNEHVI (torch).")
    args = ap.parse_args()

    out = os.path.join(RESULTS, "mo_qnehvi_rescore.json")
    if args.phase == "qnehvi":
        run_qnehvi_phase(out)
        return

    print("training permeability model (CycPeptMPDB)...", flush=True)
    perm_pred, n_perm = train_perm(args.perm_csv)
    print(f"  perm model trained on {n_perm} CycPeptMPDB rows", flush=True)
    print("loading A1 binding model...", flush=True)
    bind_pred = load_binding()

    report = {"objectives": ["binding=A1 pAffinity (real data)", "permeability=CycPeptMPDB logPapp",
                             "synthesizability=-SA_score"],
              "selectivity": "omitted — not derivable from single-target pool data (documented gap)",
              "composite_baseline": "existing hand-tuned composite ordering that selected each panel",
              "perm_model_rows": n_perm, "pools": {}}

    # PD-L1 pool (176, has COMPOSITE-ranked order via rank_composite)
    pdl1 = json.load(open(os.path.join(RESULTS, "pdl1_ranked_pool_176.json")))
    pdl1_sorted = sorted(pdl1, key=lambda r: r.get("rank_composite", 1e9))
    pdl1_seqs = [r["seq"] for r in pdl1_sorted]
    comp_order = list(range(len(pdl1_seqs)))  # already composite-ranked
    print("\n== PD-L1 pool (176) ==", flush=True)
    report["pools"]["PD-L1"] = process_pool("PD-L1", pdl1_seqs, comp_order, perm_pred, bind_pred, args.k, args)
    h = report["pools"]["PD-L1"]["hypervolume"]
    print(f"  HV composite={h['composite_topk']} greedy={h['greedy_hv_topk']} "
          f"(greedy {h['greedy_gain_vs_composite_pct']:+}%); qNEHVI pending phase 2", flush=True)

    # avb6 panel (12) — composite order = existing 'rank'
    avb6 = json.load(open(os.path.join(RESULTS, "avb6_round1_panel.json")))["panel"]
    avb6_sorted = sorted(avb6, key=lambda r: r.get("rank", 1e9))
    avb6_seqs = [r["seq"] for r in avb6_sorted]
    k_avb6 = min(args.k, len(avb6_seqs) // 1)
    k_avb6 = min(6, len(avb6_seqs))
    print(f"\n== avb6 panel ({len(avb6_seqs)}; k={k_avb6}) ==", flush=True)
    report["pools"]["avb6"] = process_pool("avb6", avb6_seqs, list(range(len(avb6_seqs))),
                                           perm_pred, bind_pred, k_avb6, args)
    report["pools"]["avb6"]["note"] = "only the 12-member panel exists (no larger avb6 pool); reranking scope limited"
    h = report["pools"]["avb6"]["hypervolume"]
    print(f"  HV composite={h['composite_topk']} greedy={h['greedy_hv_topk']} "
          f"(greedy {h['greedy_gain_vs_composite_pct']:+}%); qNEHVI pending phase 2", flush=True)

    out = os.path.join(RESULTS, "mo_qnehvi_rescore.json")
    json.dump(report, open(out, "w"), indent=2)
    print(f"\nwrote {out}", flush=True)


if __name__ == "__main__":
    main()
