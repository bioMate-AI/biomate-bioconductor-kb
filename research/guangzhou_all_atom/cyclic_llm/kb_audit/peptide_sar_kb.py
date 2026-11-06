"""Leak-safe peptide SAR rule set + knowledge channel (prototype v1).

Rules are MINED from labelled data of a stated set of TRAIN laboratories only, validated within source, stored with
provenance and a validity score, and exposed as per-peptide prior/fusion features that loop adapters can consume.

Rule types
  pair rules      matched molecular pairs (workstream 4, read-only: stratification/data/mmp_pairs_pampa.csv.gz); effect = sign*(z_b - z_a)
                  in within-source z units (raw log Papp effect kept); pooled by DerSimonian-Laird across sources.
  physchem rules  within-source Spearman of a descriptor with permeability, median across train sources.
Status (fixed here, before any held-out result is read):
  rule                    pooled 99 % CI excludes 0, AND the two sha256 source halves have the pooled sign, AND >= 3 sources,
                          AND >= 60 % of sources agree in sign.
  no_consistent_direction pooled CI includes 0 (explicitly encoded: contributes NOTHING to the prior; sd and cliff rate are stored).
  inconclusive            CI excludes 0 but halves or sources disagree (contributes nothing).
validity_score = 2*(fraction of sources agreeing in sign) - 1 for status 'rule' (0 = coin flip, 1 = unanimous), else 0.

Knowledge channel (features per peptide; all standardised WITHIN source so the scale matches within-source labels):
  K_phys   sum_i w_i * zsrc(feature_i) / sum |w_i|   over physchem rules with status 'rule'; w_i = mined median within-source rho
  K_nme    effect_z(N-Me added) * (n_nme - mean_source(n_nme))    [expected within-source shift from the pair rule]
  K_dflip  0 by construction (rule status no_consistent_direction); exposed so adapters can see the explicit "no direction" decision
  K_total  zsrc(K_phys) + zsrc(K_nme) only for rules with status 'rule'
Scope: PAMPA permeability of CycPeptMPDB-type cyclic peptides; no binding, solubility or stability rule is claimed.
Caveat for use: rules fitted on all labs must NOT be used to score those same labs in an evaluation; use fit(train_sources)
(see lolo_evaluate) so the held-out lab never enters mining.
"""
from __future__ import annotations
import hashlib, importlib.util, json, os
import numpy as np
import pandas as pd
from scipy.stats import spearmanr

HERE = os.path.dirname(os.path.abspath(__file__))
STRAT = os.path.join(HERE, "..", "stratification")
MIN_SRC_N = 20
Z = 2.576                       # 99 % intervals: calibrated on SYNTHETIC null worlds only (95 % gave a 5.5 % false-rule rate), before any real held-out result
Q_LO, Q_HI = 0.5, 99.5
PHYS = ["tpsa", "hbd", "logp", "veber_pass"]
KB_CLAIM = {"tpsa": -1, "hbd": -1, "logp": +1, "veber_pass": +1}            # direction claimed by medchem_kb physchem rules
NME_LABEL = "N-Me added (with minus without)"
DFLIP_LABEL = "D flip (D minus L)"


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


def _half(s): return int(hashlib.sha256(str(s).encode()).hexdigest(), 16) % 2


def dl_meta(effects, variances):
    """DerSimonian-Laird random-effects pooling; effects/variances per source."""
    e = np.asarray(effects, float); v = np.asarray(variances, float); ok = np.isfinite(e) & np.isfinite(v) & (v > 0); e, v = e[ok], v[ok]
    if len(e) < 2: return dict(pooled=float(e.mean()) if len(e) else np.nan, lo=np.nan, hi=np.nan, I2=np.nan, k=int(len(e)))
    w = 1 / v; fe = (w * e).sum() / w.sum(); Q = (w * (e - fe) ** 2).sum(); df = len(e) - 1
    tau2 = max(0.0, (Q - df) / (w.sum() - (w ** 2).sum() / w.sum())); ws = 1 / (v + tau2); p = (ws * e).sum() / ws.sum(); se = ws.sum() ** -0.5
    return dict(pooled=float(p), lo=float(p - Z * se), hi=float(p + Z * se), I2=float(max(0.0, (Q - df) / Q)) if Q > 0 else 0.0, k=int(len(e)))


def _status(meta, per_src, half_pooled, claimed_sign_free=True):
    if not np.isfinite(meta["lo"]): return "inconclusive", np.nan
    sgn = np.sign(meta["pooled"]); agree = float(np.mean(np.sign(per_src) == sgn)) if len(per_src) else np.nan
    excl = meta["lo"] > 0 or meta["hi"] < 0
    halves_ok = all(np.isfinite(h) and np.sign(h) == sgn for h in half_pooled)
    if not excl: return "no_consistent_direction", agree
    if halves_ok and meta["k"] >= 3 and agree >= 0.6: return "rule", agree
    return "inconclusive", agree


def mine_pair_rule(pairs: pd.DataFrame, label: str, train_sources, min_pairs=3):
    """pairs: columns source,label,sign,y_a,y_b,z_a,z_b. Returns rule dict from TRAIN sources only."""
    sub = pairs[(pairs.label == label) & pairs.source.isin(set(train_sources))].copy()
    sub["d_raw"] = sub.sign * (sub.y_b - sub.y_a); sub["d_z"] = sub.sign * (sub.z_b - sub.z_a)
    per = [];
    for s, g in sub.groupby("source"):
        if len(g) >= min_pairs: per.append((s, len(g), g.d_z.mean(), g.d_z.var(ddof=1) / len(g), g.d_raw.mean()))
    if not per:
        return dict(rule=label, status="inconclusive", n_pairs=0, n_sources=0)
    src, n, m, v, mr = map(np.array, zip(*per)); meta = dl_meta(m, v)
    hp = []
    for h in (0, 1):
        k = np.array([_half(s) == h for s in src]); hp.append(dl_meta(m[k], v[k])["pooled"] if k.sum() >= 2 else np.nan)
    status, agree = _status(meta, m, hp)
    return dict(rule=label, kind="pair", status=status, effect_z=meta["pooled"], ci_z=[meta["lo"], meta["hi"]], I2=meta["I2"],
                effect_raw_mean=float(np.average(mr, weights=n)), sd_z=float(sub.d_z.std()), cliff_frac=float((sub.d_z.abs() > 1).mean()),
                n_pairs=int(n.sum()), n_sources=int(len(src)), frac_sources_same_sign=agree, half_effects=hp,
                validity_score=(2 * agree - 1) if status == "rule" else 0.0, mined_from=sorted(map(str, src)))


def mine_phys_rule(df: pd.DataFrame, feat: str, train_sources, B=1000, seed=0):
    """df: columns Source, y_raw, <feat>. Within-source Spearman over train sources with >= MIN_SRC_N peptides."""
    d = df[df.Source.isin(set(train_sources))]; rho, src = [], []
    for s, g in d.groupby("Source"):
        if len(g) >= MIN_SRC_N and g[feat].std() > 0 and g.y_raw.std() > 0: rho.append(spearmanr(g[feat], g.y_raw)[0]); src.append(s)
    rho = np.array(rho)
    if len(rho) < 3: return dict(rule=feat, kind="physchem", status="inconclusive", n_sources=int(len(rho)))
    rng = np.random.default_rng(seed); boots = [np.median(rho[rng.integers(0, len(rho), len(rho))]) for _ in range(B)]
    lo, hi = float(np.percentile(boots, Q_LO)), float(np.percentile(boots, Q_HI)); med = float(np.median(rho))
    hp = [float(np.median(rho[[(_half(s) == h) for s in src]])) if sum(_half(s) == h for s in src) >= 2 else np.nan for h in (0, 1)]
    sgn = np.sign(med); agree = float(np.mean(np.sign(rho) == sgn)); excl = lo > 0 or hi < 0
    halves_ok = all(np.isfinite(h) and np.sign(h) == sgn for h in hp)
    status = "no_consistent_direction" if not excl else ("rule" if (halves_ok and len(rho) >= 3 and agree >= 0.6) else "inconclusive")
    return dict(rule=feat, kind="physchem", status=status, weight=med, ci=[lo, hi], n_sources=int(len(rho)), frac_sources_same_sign=agree, half_medians=hp,
                kb_claimed_sign=KB_CLAIM.get(feat), agrees_with_kb=(None if feat not in KB_CLAIM else bool(np.sign(med) == KB_CLAIM[feat])),
                validity_score=(2 * agree - 1) if status == "rule" else 0.0, mined_from=sorted(map(str, src)))


class RuleSet:
    def __init__(self, rules: dict, train_sources):
        self.rules = rules; self.train_sources = sorted(map(str, train_sources))

    def to_json(self, path):
        json.dump(dict(version="peptide_sar_kb v1", scope="PAMPA permeability, cyclic peptides (CycPeptMPDB-type); within-source z units",
                       train_sources=self.train_sources, rules=self.rules), open(path, "w"), indent=1, default=float)

    def channel(self, df: pd.DataFrame, source_col="Source") -> pd.DataFrame:
        """Per-peptide knowledge features. df needs source_col, n_nme_final, tpsa, hbd, logp, rotb (for veber_pass)."""
        d = df.copy(); out = pd.DataFrame(index=d.index)
        if "veber_pass" not in d: d["veber_pass"] = ((d.tpsa <= 140) & (d.rotb <= 10)).astype(float)
        src = d[source_col].values
        def zsrc(v):
            v = pd.Series(np.asarray(v, float), index=d.index); g = v.groupby(src)
            sd = g.transform("std").replace(0, np.nan); return ((v - g.transform("mean")) / sd).fillna(0.0)
        act = {k: r for k, r in self.rules.items() if r.get("status") == "rule" and r.get("kind") == "physchem"}
        out["K_phys"] = 0.0
        if act:
            tot = sum(abs(r["weight"]) for r in act.values())
            out["K_phys"] = sum(r["weight"] * zsrc(d[k]) for k, r in act.items()) / tot
        nme = self.rules.get(NME_LABEL, {}); out["K_nme"] = 0.0
        if nme.get("status") == "rule":
            c = pd.Series(d.n_nme_final.values.astype(float), index=d.index); out["K_nme"] = nme["effect_z"] * (c - c.groupby(src).transform("mean"))
        out["K_dflip"] = 0.0                                     # explicit: D<->L flip has no consistent direction (status recorded in rules)
        parts = [zsrc(out[k]) for k in ("K_phys", "K_nme") if (out[k].abs() > 0).any()]
        out["K_total"] = sum(parts) if parts else 0.0
        return out


def fit(pairs: pd.DataFrame, df: pd.DataFrame, train_sources) -> RuleSet:
    d = df.copy(); d["veber_pass"] = ((d.tpsa <= 140) & (d.rotb <= 10)).astype(float)
    rules = {f: mine_phys_rule(d, f, train_sources) for f in PHYS}
    rules[NME_LABEL] = mine_pair_rule(pairs, NME_LABEL, train_sources)
    rules[DFLIP_LABEL] = mine_pair_rule(pairs, DFLIP_LABEL, train_sources)
    return RuleSet(rules, train_sources)


def fuse(pred, K, n_labeled, n0=100.0):
    """Prior/fusion helper identical in form to the L2/L4 fuse arm: w = n0/(n0+n); score = (1-w) z(pred) + w z(K)."""
    z = lambda v: (np.asarray(v, float) - np.mean(v)) / (np.std(v) if np.std(v) > 0 else 1.0)
    w = n0 / (n0 + n_labeled); return (1 - w) * z(pred) + w * z(K)


def lolo_evaluate(pairs, df, eligible, shuffle_labels=False, seed=0, B=2000):
    """Leave-one-lab-out test of the RULES: for each eligible lab L, mine on the other eligible labs, score L, Spearman(K, y_within_source_z).
    shuffle_labels=True permutes labels within each source BEFORE mining (negative control: expected ~0)."""
    d = df.copy(); pr = pairs.copy()
    if shuffle_labels:
        rng = np.random.default_rng(seed)
        for s in d.Source.unique():
            m = (d.Source == s).values; d.loc[m, "y_raw"] = rng.permutation(d.loc[m, "y_raw"].values); d.loc[m, "y"] = rng.permutation(d.loc[m, "y"].values)
        ymap = d["y_raw"].to_dict(); zmap = d["y"].to_dict()
        pr["y_a"] = pr.id_a.map(ymap); pr["y_b"] = pr.id_b.map(ymap); pr["z_a"] = pr.id_a.map(zmap); pr["z_b"] = pr.id_b.map(zmap)
    rows = []
    for L in eligible:
        tr = [s for s in eligible if s != L]; rs = fit(pr, d, tr); te = d[d.Source == L]; ch = rs.channel(te)
        r = dict(lab=L, n=int(len(te)), n_active=int(sum(v.get("status") == "rule" for v in rs.rules.values())))
        for k in ("K_phys", "K_nme", "K_total"):
            r[k] = float(spearmanr(ch[k], te.y)[0]) if ch[k].std() > 0 else np.nan
        # direction agreement of mined physchem rules with the held-out lab's own within-lab direction
        for f in PHYS:
            v = rs.rules[f]; x = te[f] if f != "veber_pass" else ((te.tpsa <= 140) & (te.rotb <= 10)).astype(float)
            own = spearmanr(x, te.y_raw)[0] if x.std() > 0 else np.nan
            r["dir_" + f] = (np.sign(v["weight"]) == np.sign(own)) if (v.get("status") == "rule" and np.isfinite(own)) else np.nan
        rows.append(r)
    res = pd.DataFrame(rows); rng = np.random.default_rng(1); summ = {}
    for k in ("K_phys", "K_nme", "K_total"):
        v = res[k].dropna().values
        if len(v) >= 4:
            b = [np.median(v[rng.integers(0, len(v), len(v))]) for _ in range(B)]
            summ[k] = dict(median=float(np.median(v)), ci95=[float(np.percentile(b, 2.5)), float(np.percentile(b, 97.5))], n_labs=int(len(v)), n_pos=int((v > 0).sum()))
    return res, summ
