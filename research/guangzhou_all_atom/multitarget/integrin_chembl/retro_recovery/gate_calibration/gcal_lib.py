"""Calibrated validity gate (docs/20261031_GATE_CALIBRATION_PREREG.md, procedure (a)). Pure statistics on the compact gate records of
gate_positive_control (gpc_lib.compact); numpy/scipy only so it can be unit-tested without rdkit."""
import json, math, hashlib
import numpy as np
from scipy.stats import norm, beta

PRIMARY = ["C1_atomlm_typicality", "C2_multiproxy_leave_fold_out", "C3_morgan_fp_leave_fold_out"]
SEC18 = ["heavy", "charge", "n_frac", "o_frac", "has_s", "has_halogen", "ncaa_frac", "n_arom", "tpsa", "logp", "hbd", "hba", "rotb", "fsp3", "ring", "n_rings", "in_corpus", "in_cycpeptmpdb"]
ITEM = ["C4_censored_label", "C5_assay_IC50_only", "C5_assay_has_Ki_or_Kd", "C5_assay_has_EC50"]
PRIM_LEVEL = 1 - 0.05 / 3; L18 = 1 - 0.05 / 18; L22 = 1 - 0.05 / 22
SIGMA_FAM = 0.2014; MIN_FAM = 8; MIN_NULL = 30; ALPHA = 0.05; Z90 = 1.645


def delta(F):
    return 0.5 * 2.8 * SIGMA_FAM / math.sqrt(F)


def zcrit(level):
    return float(norm.ppf(1 - (1 - level) / 2))


def controls(rec):
    out = {}
    for k, v in rec["primary"].items():
        if v is None: continue
        out[k] = dict(point=v["point"], lo=v["lo"], hi=v["hi"], n=v["n_families"], level=PRIM_LEVEL)
    for k, v in rec["secondary"].items():
        out[k] = dict(point=v["point"], lo=v["lo"], hi=v["hi"], n=v["n_families"], level=L22 if k in ITEM else L18)
    return out


def zvals(rec):
    """standardised control values; returns (z, se) for evaluable controls only"""
    z, se = {}, {}
    for k, c in controls(rec).items():
        if c["point"] is None or c["lo"] is None or c["hi"] is None or c["n"] < MIN_FAM: continue
        w = c["hi"] - c["lo"]
        if not w > 0: continue
        s = w / (2 * zcrit(c["level"])); se[k] = s; z[k] = (c["point"] - 0.5) / s
    return z, se


def rec_type(rec):
    return "I" if "C4_censored_label" in rec["secondary"] else "M"


def fit(null_records_by_type):
    """null_records_by_type: {'I': [rec,...], 'M': [rec,...]} -> frozen constants {type: {kappa:{k:..}, q:.., n_null:.., n_obs:{k:..}, untested:[..]}}"""
    cal = {}
    for typ, recs in null_records_by_type.items():
        zs = [zvals(r)[0] for r in recs]; names = sorted({k for z in zs for k in z})
        kappa, nobs, untested = {}, {}, []
        for k in names:
            v = np.array([z[k] for z in zs if k in z]); nobs[k] = int(len(v))
            if len(v) < MIN_NULL: untested.append(k); continue
            kappa[k] = float(np.sqrt(np.mean(v ** 2)))
        T = []
        for z in zs:
            t = [abs(z[k]) / kappa[k] for k in z if k in kappa]
            if t: T.append(max(t))
        cal[typ] = dict(kappa=kappa, q=float(np.quantile(T, 1 - ALPHA)), n_null=len(recs), n_T=len(T), n_obs=nobs, untested=untested, T_null_quantiles={str(p): float(np.quantile(T, p)) for p in (0.5, 0.9, 0.95, 0.99)})
    return cal


def assess(rec, cal, typ=None):
    typ = typ or rec_type(rec); C = cal[typ]; z, se = zvals(rec)
    zt = {k: z[k] / C["kappa"][k] for k in z if k in C["kappa"]}
    T = max(abs(v) for v in zt.values()) if zt else float("nan")
    flagged = sorted(k for k, v in zt.items() if abs(v) > C["q"])
    prim_ok = all(k in z for k in PRIMARY)
    biased = bool(zt) and T > C["q"]
    Fp = [rec["primary"][k]["n_families"] for k in PRIMARY if rec["primary"].get(k)]
    d = delta(min(Fp)) if Fp else float("nan")
    eq = {}
    for k in PRIMARY:
        if k in z and k in C["kappa"]:
            eq[k] = bool(abs(rec["primary"][k]["point"] - 0.5) + Z90 * C["kappa"][k] * se[k] <= d)
    eq_ok = prim_ok and all(eq.get(k, False) for k in PRIMARY)
    status = "BIASED" if biased else "UNVERIFIABLE" if not prim_ok else "NOT_EQUIVALENT" if not eq_ok else "VALID"
    return dict(status=status, T=T, q=C["q"], flagged=flagged, delta=d, equivalent=eq, z_std={k: round(v, 3) for k, v in zt.items()})


def registered_biased(rec):
    return rec["status"] == "NOT_VALID_BIASED"


def registered_valid(rec):
    return rec["status"] == "VALID"


def cp_ci(k, n, level=0.95):
    a = (1 - level) / 2
    lo = 0.0 if k == 0 else float(beta.ppf(a, k, n - k + 1)); hi = 1.0 if k == n else float(beta.ppf(1 - a, k + 1, n - k))
    return [lo, hi]


def rate(flags):
    flags = list(flags); n = len(flags); k = int(sum(flags))
    return dict(k=k, n=n, p=(k / n if n else float("nan")), ci=(cp_ci(k, n) if n else [float("nan")] * 2))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()


def read_jsonl(path):
    with open(path) as f: return [json.loads(l) for l in f if l.strip()]
