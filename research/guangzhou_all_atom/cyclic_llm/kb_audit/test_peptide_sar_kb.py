"""Controls for peptide_sar_kb: planted effects recovered; D-flip with no planted effect is encoded as no_consistent_direction;
shuffled labels give no rules; held-out labs never enter mining; a pure between-source confound is not turned into a rule; channel is
source-standardised and carries no label information. Run: python3 -m pytest -q test_peptide_sar_kb.py"""
import numpy as np, pandas as pd
import peptide_sar_kb as P

def synth(n_src=10, n_pairs=60, n_pep=60, nme_effect=0.5, tpsa_beta=-0.5, seed=0, confound=0.0):
    rng = np.random.default_rng(seed); pairs, rows = [], []; pid = 0
    for s in range(n_src):
        off = rng.normal(0, 2.0); src = f"S{s:02d}"
        for _ in range(n_pep):
            tpsa = rng.normal(120 + confound * off * 10, 15); nme = rng.integers(0, 6); rotb = rng.integers(3, 14)
            y = off + tpsa_beta * (tpsa - 120) / 15 + 0.0 * nme + rng.normal(0, 1); rows.append(dict(id=pid, Source=src, tpsa=tpsa, hbd=rng.integers(2, 8), logp=rng.normal(2, 1), rotb=rotb, n_nme_final=nme, y_raw=y)); pid += 1
        ys = {r["id"]: r["y_raw"] for r in rows if r["Source"] == src}; sd = np.std(list(ys.values()))
        for _ in range(n_pairs):
            a = rng.normal(off, 1); base = a
            lab = P.NME_LABEL if rng.random() < 0.5 else P.DFLIP_LABEL; eff = nme_effect if lab == P.NME_LABEL else 0.0
            b = base + eff + rng.normal(0, 0.7)
            pairs.append(dict(id_a=-1, id_b=-1, source=src, label=lab, sign=1, y_a=a, y_b=b, z_a=(a - off) / 1.0, z_b=(b - off) / 1.0))
    d = pd.DataFrame(rows).set_index("id"); d["y"] = d.groupby("Source").y_raw.transform(lambda v: (v - v.mean()) / v.std())
    return pd.DataFrame(pairs), d

def test_planted_pair_effect_recovered_and_dflip_has_no_direction():
    pairs, d = synth(); rs = P.fit(pairs, d, d.Source.unique())
    nme = rs.rules[P.NME_LABEL]; df = rs.rules[P.DFLIP_LABEL]
    assert nme["status"] == "rule" and nme["ci_z"][0] > 0 and 0.3 < nme["effect_z"] < 0.7
    assert df["status"] == "no_consistent_direction" and df["validity_score"] == 0.0

def test_planted_physchem_rule_recovered_with_correct_sign():
    pairs, d = synth(); rs = P.fit(pairs, d, d.Source.unique()); r = rs.rules["tpsa"]
    assert r["status"] == "rule" and r["weight"] < -0.2 and r["agrees_with_kb"] is True

def _shuffled(seed):
    pairs, d = synth(seed=seed); rng = np.random.default_rng(1000 + seed)
    for s in d.Source.unique():
        m = d.Source == s; d.loc[m, "y_raw"] = rng.permutation(d.loc[m, "y_raw"].values)
        pm = (pairs.source == s).values; v = rng.permutation(np.concatenate([pairs.loc[pm, "y_a"].values, pairs.loc[pm, "y_b"].values])); n = pm.sum(); off = v.mean()
        pairs.loc[pm, "y_a"] = v[:n]; pairs.loc[pm, "y_b"] = v[n:]; pairs.loc[pm, "z_a"] = v[:n] - off; pairs.loc[pm, "z_b"] = v[n:] - off
    return pairs, d

def test_shuffled_labels_false_rule_rate_is_low():
    fr = tot = 0
    for seed in range(100):
        pairs, d = _shuffled(seed); rs = P.fit(pairs, d, d.Source.unique())
        for v in rs.rules.values(): tot += 1; fr += v["status"] == "rule"
    assert fr / tot <= 0.03, (fr, tot)           # null false-rule rate (600 rule-tests)

def test_heldout_lab_labels_never_enter_mining():
    pairs, d = synth(); train = [s for s in d.Source.unique() if s != "S03"]
    r1 = P.fit(pairs, d, train)
    p2 = pairs.copy(); m = p2.source == "S03"; p2.loc[m, ["y_a", "y_b", "z_a", "z_b"]] = 999.0
    d2 = d.copy(); d2.loc[d2.Source == "S03", "y_raw"] = -999.0
    r2 = P.fit(p2, d2, train)
    for k in r1.rules: assert r1.rules[k].get("effect_z", r1.rules[k].get("weight")) == r2.rules[k].get("effect_z", r2.rules[k].get("weight"))

def test_between_source_confound_not_a_physchem_rule():
    pairs, d = synth(tpsa_beta=0.0, confound=1.0); rs = P.fit(pairs, d, d.Source.unique()); assert rs.rules["tpsa"]["status"] != "rule"

def test_channel_is_label_free_and_source_standardised():
    pairs, d = synth(); rs = P.fit(pairs, d, d.Source.unique()); ch = rs.channel(d.drop(columns=["y", "y_raw"]))
    assert ch.K_dflip.abs().sum() == 0 and abs(ch.K_phys.groupby(d.Source).mean()).max() < 1e-9

def test_channel_recovers_planted_signal_on_held_out_lab():
    pairs, d = synth(n_src=12); train = [s for s in d.Source.unique() if s != "S05"]; rs = P.fit(pairs, d, train)
    te = d[d.Source == "S05"]; ch = rs.channel(te); from scipy.stats import spearmanr
    assert spearmanr(ch.K_phys, te.y)[0] > 0.3
