"""Shared helpers: paths, amino-acid scales, domain table, statistics.

Raw Landry-lab data (CC BY-NC-ND) is NEVER stored in the repo; it is read from
$PCA_RAW (default: the session scratchpad).  Only code and derived summary
numbers are committed.
"""
import os, json
import numpy as np

RAW = os.environ.get(
    "PCA_RAW",
    "/private/tmp/claude-501/-Users-kky-biomate-review/195b4da4-5c44-48ae-a4e1-005d493239c0/scratchpad/raw",
)
OUT_TABLE = os.path.join(os.path.dirname(RAW), "tables")
HERE = os.path.dirname(os.path.abspath(__file__))

AAS = "ACDEFGHIKLMNPQRSTVWY"
KD = dict(A=1.8, R=-4.5, N=-3.5, D=-3.5, C=2.5, Q=-3.5, E=-3.5, G=-0.4, H=-3.2, I=4.5,
          L=3.8, K=-3.9, M=1.9, F=2.8, P=-1.6, S=-0.8, T=-0.7, W=-0.9, Y=-1.3, V=4.2)
CHARGE = dict({a: 0.0 for a in AAS}, K=1.0, R=1.0, D=-1.0, E=-1.0, H=0.1)
VOL = dict(A=88.6, R=173.4, N=114.1, D=111.1, C=108.5, Q=143.8, E=138.4, G=60.1, H=153.2,
           I=166.7, L=166.7, K=168.6, M=162.9, F=189.9, P=112.7, S=89.0, T=116.1, W=227.8,
           Y=193.6, V=140.0)
AROM = set("FWYH")

# Domains: accession from UniProt (as listed in the repo's PRM_Master.csv), sequence = domain boundary
# used in the repo.  Domain id = PRM number used throughout the data files.
DOMAINS = {
    "152": dict(cls="SH3", gene="SHO1", uniprot="P40073", seq="GDTLGLYSDIGDDNFIYKAKALYPYDADDDDAYEISFEQNEILQVSDIEGRWWKARRANGETGIIPSNYVQLIDGPEEMHR"),
    "246": dict(cls="SH3", gene="ARHGAP26", uniprot="Q9UNA1", seq="RKAKALYACKAEHDSELSFTAGTVFDNVHPSQEPGWLEGTLNGKTGLIPENYVEFL"),
    "250": dict(cls="SH3", gene="EPS8L1", uniprot="Q8TE68", seq="KWVLCNYDFQARNSSELSVKQRDVLEVLDDSRKWWKVRDPAGQEGYVPYNILTPYP"),
    "299": dict(cls="SH3", gene="SNX9", uniprot="Q9Y5X1", seq="TKARVMYDFAAEPGNNELTVNEGEIITITNPDVGGGWLEGRNIKGERGLVPTDYVEILP"),
    "363": dict(cls="PDZ", gene="TJP1 (PDZ3)", uniprot="Q07157", seq="SMKLVKFRKGDSVGLRLAGGNDVGIFVAGVLEDSPAAKEGLEEGDQILRVNNVDFTNIIREEAVLFLLDLPKGEEVTILAQK"),
    "366": dict(cls="PDZ", gene="TIAM1 (PDZ1)", uniprot="Q13009", seq="MQLYVPQPEEDIYELLYKEIEICPKVTQSIHIEKSDTAADTYGFSLSSVEEDGIRRLYVNSVKETGLASKKGLKAGDEILEINNRAADALNSSMLKDFLSQPSLGLLVRTYPELEEG"),
    "385": dict(cls="PDZ", gene="PDLIM4 (PDZ1)", uniprot="P50479", seq="MPHSVTLRGPSPWGFRLVGGRDFSAPLTISRVHAGSKAALAALCPGDLIQAINGESTELMTHLEAQNRIKGCHDHLTLSVSRPEGRSWPSAPDDSKAQAHRIHIDPEIQD"),
}


def hyd(seq):
    return float(np.mean([KD[a] for a in seq if a in KD]))


def charge(seq):
    return float(sum(CHARGE.get(a, 0) for a in seq))


def spearman(x, y):
    from scipy.stats import spearmanr
    x = np.asarray(x, float); y = np.asarray(y, float)
    ok = np.isfinite(x) & np.isfinite(y)
    if ok.sum() < 5 or np.std(x[ok]) == 0 or np.std(y[ok]) == 0:
        return float("nan")
    return float(spearmanr(x[ok], y[ok])[0])


def boot_ci(x, y, n=500, seed=0):
    """Percentile bootstrap CI of Spearman over peptides."""
    rng = np.random.default_rng(seed)
    x = np.asarray(x, float); y = np.asarray(y, float)
    ok = np.isfinite(x) & np.isfinite(y); x, y = x[ok], y[ok]
    if len(x) < 5:
        return (float("nan"), float("nan"))
    from scipy.stats import rankdata
    vals = []
    for _ in range(n):
        i = rng.integers(0, len(x), len(x))
        a, b = x[i], y[i]
        if np.std(a) == 0 or np.std(b) == 0:
            continue
        vals.append(np.corrcoef(rankdata(a), rankdata(b))[0, 1])
    return (float(np.percentile(vals, 2.5)), float(np.percentile(vals, 97.5)))


def domain_ci(rhos, n=5000, seed=0):
    """Mean over domains with (a) t-interval and (b) percentile bootstrap over domains."""
    from scipy import stats
    r = np.array([v for v in rhos if np.isfinite(v)], float)
    if len(r) < 2:
        return dict(mean=float(r.mean()) if len(r) else float("nan"), n=len(r), t_lo=float("nan"), t_hi=float("nan"), b_lo=float("nan"), b_hi=float("nan"))
    m = r.mean(); se = r.std(ddof=1) / np.sqrt(len(r)); tcrit = stats.t.ppf(0.975, len(r) - 1)
    rng = np.random.default_rng(seed)
    bs = [r[rng.integers(0, len(r), len(r))].mean() for _ in range(n)]
    return dict(mean=float(m), n=len(r), t_lo=float(m - tcrit * se), t_hi=float(m + tcrit * se),
                b_lo=float(np.percentile(bs, 2.5)), b_hi=float(np.percentile(bs, 97.5)))
