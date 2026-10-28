"""Step 3-4: baselines + arms S1a / S1b-KB / S1b-leaky / S1b-induction, evaluation with harness.py (PREREG A3).
Writes data/baseline_scores_{M,I}.csv.gz, data/arm_scores_{M,I}.csv.gz, results/results_{M,I}.json, results/component_log.json.
Every arm/baseline is defined in PREREG §11; nothing here is tuned on outcomes."""
import os, sys, json, gzip, hashlib, collections
import numpy as np, pandas as pd
from rdkit import Chem, DataStructs, RDLogger
from rdkit.Chem import AllChem
RDLogger.DisableLog("rdApp.*")
HERE = os.path.dirname(os.path.abspath(__file__)); DATA = f"{HERE}/data"; RES = f"{HERE}/results"; os.makedirs(RES, exist_ok=True)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.abspath(f"{HERE}/../../../cyclic_llm"))
import chem, harness as H
SEED = 20261028
SMOKE = os.environ.get("RETRO_SMOKE") == "1"          # smoke = tiny slice to test code paths, results not kept

C = pd.read_csv(f"{DATA}/compounds.csv.gz").set_index("compound_id"); P = pd.read_csv(f"{DATA}/pair_labels.csv.gz"); T = pd.read_csv(f"{DATA}/targets.csv")
fam = dict(zip(T.target_key, T.family)); genes = dict(zip(T.target_key, T.genes.fillna("")))
IM = pd.read_csv(f"{DATA}/items_M.csv.gz"); II = pd.read_csv(f"{DATA}/items_I.csv.gz")
if SMOKE:
    keep = sorted(IM.target_key.unique())[:12]; IM = IM[IM.target_key.isin(keep)]; keep = sorted(II.target_key.unique())[:6]; II = II[II.target_key.isin(keep)]
COMPONENTS = {}

# ---------- features + fingerprints for every compound that can appear (items + reference sets)
need = sorted(set(IM.compound_id) | set(II.compound_id) | set(P.compound_id))      # all labelled compounds (positives = B3 references, inactives = induction non-actives)
gen = AllChem.GetMorganGenerator(radius=2, fpSize=2048, includeChirality=True)
fp = {}
for c in need:
    m = Chem.MolFromSmiles(C.loc[c, "iso_smiles"]); fp[c] = np.array(list(gen.GetFingerprintAsNumPy(m)), dtype=np.uint8) if m is not None else np.zeros(2048, np.uint8)
idx = {c: i for i, c in enumerate(need)}; X = np.stack([fp[c] for c in need]).astype(np.float32); xs = X.sum(1)
flat_id = pd.factorize(C.loc[need, "flat_key"])[0]
pos_pairs = P[P.label == "pos"]; lab_pairs = P
posfams = pos_pairs.assign(f=pos_pairs.target_key.map(fam)).groupby("compound_id").f.apply(set).to_dict()
depth = lab_pairs.groupby("compound_id").target_key.apply(set).to_dict()
is_itg = lambda t: "ITG" in genes[t].upper()


def tanimoto_rows(ia, ib):
    inter = X[ia] @ X[ib].T
    return inter / (xs[ia][:, None] + xs[ib][None, :] - inter + 1e-9)


def baselines(items):
    rng = np.random.default_rng(SEED); out = []
    for t, g in items.groupby("target_key", sort=True):
        cids = g.compound_id.values; ii = np.array([idx[c] for c in cids]); F = fam[t]
        d = C.loc[cids]
        cols = {"B0_random": rng.random(len(g)), "B1_rgd": d.rgd.astype(float).values, "B1_heavy_pos": d.heavy.values.astype(float), "B1_heavy_neg": -d.heavy.values.astype(float),
                "B1_charge_pos": d.charge.values.astype(float), "B1_charge_neg": -d.charge.values.astype(float)}
        # B3: max Tanimoto to positives of OTHER-family targets, never positives of this family; same flat structure excluded
        refs = [c for c in need if (c in posfams) and F not in posfams[c]]
        ri = np.array([idx[c] for c in refs]); S = tanimoto_rows(ii, ri)
        S[flat_id[ii][:, None] == flat_id[ri][None, :]] = -1.0
        b3 = S.max(1)
        cols["B3_nn_pos"] = b3; cols["B3_nn_neg"] = -b3
        dep = np.array([len(depth.get(c, set()) - {t}) for c in cids], float)
        cols["B4_depth_pos"] = dep; cols["B4_depth_neg"] = -dep
        for k, v in cols.items():
            out.append(pd.DataFrame(dict(arm=k, target_key=t, compound_id=cids, score=v)))
    return pd.concat(out, ignore_index=True)


# ---------- knowledge arms
KB_TARGETS = {"avb6": lambda g: "ITGB6" in g, "pdl1": lambda g: "CD274" in g, "a4b1": lambda g: "ITGA4" in g and "ITGB1" in g, "a4b7": lambda g: "ITGA4" in g and "ITGB7" in g,
              "c5": lambda g: "C5" in g.split(","), "fcrn": lambda g: "FCGRT" in g, "il23": lambda g: any(x.startswith("IL23") for x in g.split(",")), "tnfa": lambda g: "TNF" in g.split(",")}


def kb_key(t):
    g = genes[t].upper()
    for k, f in KB_TARGETS.items():
        if f(g): return k
    return None


try:
    import experience_kb
    KBENT = {}
    for k in KB_TARGETS:
        try:
            ents = experience_kb.all_entries(k); KBENT[k] = ents
        except Exception as e:
            COMPONENTS[f"experience_kb.all_entries({k})"] = f"ERROR {type(e).__name__}: {str(e)[:120]}"
    COMPONENTS["experience_kb"] = f"imported; resolved entries for {sorted(k for k in KBENT)}; counts {{{', '.join(f'{k}:{len(v)}' for k, v in KBENT.items())}}}"
except Exception as e:
    KBENT = {}; COMPONENTS["experience_kb"] = f"IMPORT FAILED {type(e).__name__}: {str(e)[:160]} -> S1b-KB falls back to nothing (reported unavailable)"
# a KB target "requires RGD" only if it resolves a pharmacophore entry of target_class integrin-MIDAS (an earlier text-search version matched FTO-genus text of PD-L1 and was wrong)
kb_requires_rgd = {k: any(getattr(e, "id", "").endswith(":pharmacophore") and (getattr(e, "scope", {}) or {}).get("target_class") == "integrin-MIDAS" for e in v) for k, v in KBENT.items()}
COMPONENTS["experience_kb resolved entry ids"] = {k: [getattr(e, "id", "?") for e in v] for k, v in KBENT.items()}
COMPONENTS["kb_requires_RGD(resolved entries mention RGD)"] = kb_requires_rgd


def s1a(items):
    out = []
    for t, g in items.groupby("target_key", sort=True):
        sc = C.loc[g.compound_id, "rgd"].astype(float).values if is_itg(t) else np.zeros(len(g))
        out.append(pd.DataFrame(dict(arm="S1a_rules", target_key=t, compound_id=g.compound_id.values, score=sc)))
    return pd.concat(out, ignore_index=True)


def s1b_kb(items):
    out = []
    for t, g in items.groupby("target_key", sort=True):
        k = kb_key(t); sc = np.zeros(len(g))
        if k and kb_requires_rgd.get(k): sc = C.loc[g.compound_id, "rgd"].astype(float).values
        out.append(pd.DataFrame(dict(arm="S1b_KB", target_key=t, compound_id=g.compound_id.values, score=sc)))
    return pd.concat(out, ignore_index=True)


def kb_actives_fp():
    import test_chem as tc
    res = {}
    for k in ("avb6",):
        kb = json.load(open(os.path.abspath(f"{HERE}/../../../cyclic_llm/target_kb/{k}.json")))
        hs = list(kb["examples"].get("actives", [])) + [c["helm"] for c in kb.get("controls", []) if "helm" in c]; vecs = []
        for h in hs:
            toks = h.strip()[6:-1].split("-"); seq = ""; d = []; nm = []
            for i, tkn in enumerate(toks):
                if tkn.startswith("["):
                    tkn = tkn[1:-1]
                    if tkn.startswith("d") and len(tkn) == 2: seq += tkn[1]; d.append(i)
                    elif tkn.startswith("NMe") and len(tkn) == 4: seq += tkn[3]; nm.append(i)
                    else: seq = None; break
                else: seq += tkn
            if seq is None: continue
            m = tc.cyclize(seq, d_idx=tuple(d), nme_idx=tuple(nm)); vecs.append(np.array(list(gen.GetFingerprintAsNumPy(m)), np.float32))
        res[k] = np.stack(vecs)
    return res


def s1b_leaky(items):
    A = kb_actives_fp()["avb6"]; out = []
    for t, g in items.groupby("target_key", sort=True):
        ii = np.array([idx[c] for c in g.compound_id]); sc = np.zeros(len(g))
        if kb_key(t) == "avb6":
            inter = X[ii] @ A.T; sc = (inter / (xs[ii][:, None] + A.sum(1)[None, :] - inter + 1e-9)).max(1)
        out.append(pd.DataFrame(dict(arm="S1b_leaky_KBactives", target_key=t, compound_id=g.compound_id.values, score=sc)))
    return pd.concat(out, ignore_index=True)


def s1b_induction(items):
    import rule_induction as RI
    COMPONENTS["rule_induction.induce"] = "imported; predicates() replaced by SMILES predicates (original is HELM/avb6-specific); induce() called unchanged"
    pred = {}
    for c in need:
        r = C.loc[c]; pred[c] = {"has_rgd": bool(r.rgd), "has_d": False, "has_nsub": False, "arom_ge1": r.n_arom >= 1, "arom_ge2": r.n_arom >= 2, "charge_pos": r.charge >= 1, "charge_nonpos": r.charge <= 0,
                                 "ring_ge15": r.ring >= 15, "heavy_ge80": r.heavy >= 80, "ncaa": r.stratum == "ncaa_peptide"}
    # D / N-substituted flags need the classifier (cheap to recompute for the needed compounds)
    for c in need:
        cl = chem.classify(chem.parse(C.loc[c, "iso_smiles"])); pred[c]["has_d"] = cl["n_d"] > 0; pred[c]["has_nsub"] = cl["n_nsub"] > 0
    RI.predicates = lambda cid: pred[cid]
    rng = np.random.default_rng(SEED); out = []; rules_log = {}
    posp = pos_pairs.assign(f=pos_pairs.target_key.map(fam)); inap = P[P.label == "inactive"].assign(f=lambda d: d.target_key.map(fam))
    for F, tg in items.assign(f=items.target_key.map(fam)).groupby("f"):
        act = sorted(set(posp[posp.f != F].compound_id)); non = sorted(set(inap[inap.f != F].compound_id))
        draws = []
        for _ in range(100):
            res = RI.induce(list(rng.choice(act, 5, replace=False)), list(rng.choice(non, 5, replace=False))); draws.append(res["rule"])
        rules_log[F] = collections.Counter(tuple(r) for r in draws).most_common(3)
        for t, g in tg.groupby("target_key", sort=True):
            sc = np.array([np.mean([all(pred[c][k] for k in r) for r in draws]) for c in g.compound_id])
            out.append(pd.DataFrame(dict(arm="S1b_induction", target_key=t, compound_id=g.compound_id.values, score=sc)))
    json.dump({k: [(list(r), n) for r, n in v] for k, v in rules_log.items()}, open(f"{RES}/induced_rules_I{'_smoke' if SMOKE else ''}.json", "w"), indent=1)
    return pd.concat(out, ignore_index=True)


# ---------- run
def run(which, items):
    base = baselines(items); arms = [s1a(items), s1b_kb(items)]
    if which == "M": arms.append(s1b_leaky(items))
    if which == "I": arms.append(s1b_induction(items))
    A = pd.concat(arms, ignore_index=True)
    if not SMOKE:
        base.to_csv(f"{DATA}/baseline_scores_{which}.csv.gz", index=False, compression=dict(method="gzip", mtime=0)); A.to_csv(f"{DATA}/arm_scores_{which}.csv.gz", index=False, compression=dict(method="gzip", mtime=0))
    allsc = pd.concat([base, A]); names_b = sorted(base.arm.unique()); armsd = {a: g[["target_key", "compound_id", "score"]] for a, g in allsc.groupby("arm")}
    tfam = T[["target_key", "family", "genes"]]
    results = {}
    # compound/pair sets for subsets
    ki_kd_pos = set(zip(P[(P.label == "pos") & P.assay_types.str.contains("Ki|Kd")].target_key, P[(P.label == "pos") & P.assay_types.str.contains("Ki|Kd")].compound_id))
    subsets = {"all": None, "integrin_targets": set(t for t in items.target_key.unique() if is_itg(t)), "avb6_targets": set(t for t in items.target_key.unique() if "ITGB6" in genes[t].upper()),
               "KB_mapped_targets": set(t for t in items.target_key.unique() if kb_key(t))}
    for name, sub in subsets.items():
        if sub is not None and len(sub) == 0: continue
        results[name] = H.evaluate(items, tfam, armsd, names_b, subset=sub)
    for s in ("peptide", "ncaa_peptide", "non_peptide_macrocycle"):
        it = items[items.compound_id.map(C.stratum) == s]
        if it.groupby("target_key").label.nunique().eq(2).sum() >= 5: results[f"stratum_{s}"] = H.evaluate(it, tfam, armsd, names_b)
    it = items[(items.label == 0) | pd.Series([(t, c) in ki_kd_pos for t, c in zip(items.target_key, items.compound_id)], index=items.index)]
    results["sensitivity_Ki_Kd_positives_only"] = H.evaluate(it, tfam, armsd, names_b)
    return results


if __name__ == "__main__":
    out = {}
    for which, items in (("M", IM), ("I", II)):
        out[which] = run(which, items)
        if not SMOKE: json.dump(out[which], open(f"{RES}/results_{which}.json", "w"), indent=1)
    COMPONENTS["BioMate workflow DB / UnifiedWorkflowSearch"] = "audited (docking/QSAR/boltz/OpenFE workflows listed in PREREG 11.1); NOT run (need per-target receptor or per-target training data)"
    COMPONENTS["loop.py/loop_batch.py -> physics_batch (Boltz-2, MM-GBSA) -> execution_grader (S2)"] = "NOT run: cost estimate only (PREREG 11.4)"
    COMPONENTS["medchem_kb / medchem_kb_product / ingested KBs"] = "audited; not a binding scorer; no structures in ingested JSONs; not run"
    COMPONENTS["acceptance_gate / pharmacophore_knowledge / knowledge_liability_flags"] = "HELM-input; only RGD predicate re-implemented on SMILES (chem.has_rgd) for S1a; H2-H8 not applicable to SMILES table"
    COMPONENTS["S3 plug-in (v4 / atom-LM)"] = "harness.py ready; awaiting score files from workstream 1"
    json.dump(COMPONENTS, open(f"{RES}/component_log{'_smoke' if SMOKE else ''}.json", "w"), indent=1)
    print(json.dumps(COMPONENTS, indent=1))
    for w in out:
        for sub in ("all",):
            r = out[w][sub]; print(w, sub, "strongest baseline auc:", r["strongest_baseline_auc"], "| arms vs strongest:", {k: (round(v["point"], 3), v["verdict"]) for k, v in r.get("vs_strongest_auc", {}).items()})
