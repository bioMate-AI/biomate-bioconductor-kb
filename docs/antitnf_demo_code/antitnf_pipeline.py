#!/usr/bin/env python3
"""
Anti-TNF (infliximab) response prediction in IBD from baseline mucosal transcriptome.

HONEST CREDIBILITY DEMONSTRATION — NOT a novelty claim.
Prior art: anti-TNF response prediction from GSE12251/GSE14580/GSE16879 is well studied
(Arijs et al. 2009 Gut / 2009 PLoS ONE; many ML re-analyses since). The mechanism-
constrained-ML class (P-NET, DrugCell, DCell, consDeepSignaling, PBAC/TCRP) already exists.
This is single-arm responder classification, NOT a randomized biomarker x treatment
interaction test — so gate-3 interaction logic does NOT apply here.

Datasets (public GEO, all GPL570 Affymetrix HG-U133 Plus 2.0):
  - GSE12251  : UC, ACT1 cohort (independent), pre-treatment mucosal biopsy
  - GSE14580  : UC, Leuven/Arijs cohort, pre-treatment mucosal biopsy
  - GSE16879  : UC + CD, Leuven/Arijs cohort, pre + post; labels in GSM titles (UCR*_beforeT etc.)

IMPORTANT cohort-overlap caveat: GSE14580 and GSE16879 are BOTH the Leuven/Arijs cohort and
share patients. The only leakage-free cross-dataset transfer is train(GSE16879) -> test(GSE12251),
because GSE12251 is the independent ACT1 cohort. We therefore report that transfer and explicitly
flag 14580<->16879 as same-cohort (not an independent test).
"""
import os, sys, io, re, json, time, gzip, urllib.request, warnings
import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")
np.random.seed(42)

OUT = os.environ.get("ANTITNF_OUT", "/tmp/antitnf_out")
os.makedirs(OUT, exist_ok=True)

GEO_MATRIX = {
    # series_matrix files (contain normalized expression + sample metadata headers)
    "GSE12251": "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE12nnn/GSE12251/matrix/GSE12251_series_matrix.txt.gz",
    "GSE14580": "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE14nnn/GSE14580/matrix/GSE14580_series_matrix.txt.gz",
    "GSE16879": "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE16nnn/GSE16879/matrix/GSE16879_series_matrix.txt.gz",
}
# GPL570 annotation (probe -> gene symbol)
GPL570_ANNOT = "https://ftp.ncbi.nlm.nih.gov/geo/platforms/GPLnnn/GPL570/annot/GPL570.annot.gz"

# ---------------------------------------------------------------------------
# Mechanism gene set: TNF/NF-kB + inflammatory response (the anti-TNF mechanism)
# Union of Hallmark TNFA_SIGNALING_VIA_NFKB (core members) + key TNF/TNFR/NFKB genes.
# We keep a curated core so the demo is self-contained (no MSigDB download needed);
# these are canonical TNF-alpha/NF-kB signaling and inflammatory-response genes.
# ---------------------------------------------------------------------------
MECHANISM_GENES = sorted(set("""
TNF TNFRSF1A TNFRSF1B TNFAIP2 TNFAIP3 TNFAIP6 TNFAIP8 TRAF1 TRAF2 TRAF3 TRAF6
NFKB1 NFKB2 NFKBIA NFKBIE REL RELA RELB IKBKB IKBKG CHUK MAP3K8 RIPK1 RIPK2
IL1A IL1B IL1R1 IL1RN IL6 IL6R IL8 CXCL1 CXCL2 CXCL3 CXCL5 CXCL9 CXCL10 CXCL11
CCL2 CCL20 CCL3 CCL4 CCL5 IL18 IL23A IL17A IL17RA IL12B PTGS2 NOS2 SELE VCAM1
ICAM1 CD40 CD40LG CD44 CSF1 CSF2 CSF3 LIF PTX3 SOD2 BIRC3 BCL3 GADD45B JUN JUNB
FOS FOSB EGR1 EGR2 EGR3 DUSP1 DUSP2 DUSP4 DUSP5 ATF3 NR4A1 NR4A2 NR4A3 IER2 IER3
KLF6 CEBPB CEBPD SGK1 PLAU PLAUR SERPINE1 SERPINB2 F3 EDN1 CCND1 MYC RELT LTB
LTA TNFSF15 TNFSF13B TNFRSF9 TNFRSF11B IRF1 STAT1 STAT3 SOCS3 OSM OSMR TREM1
S100A8 S100A9 S100A12 MMP1 MMP3 MMP9 MMP12 TIMP1 DEFA5 DEFA6 REG1A REG1B REG3A
LCN2 CHI3L1 PI3 SAA1 SAA2 CRP HP ORM1 FCGR3B FPR1 FPR2 CXCR1 CXCR2 OLR1 IL1RL1
""".split()))

# ---------------------------------------------------------------------------
def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)

def download(url, dest, retries=5):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        # validate gzip integrity for cached file
        try:
            with gzip.open(dest, "rb") as g:
                g.read(1024)
            log("cached", dest); return dest
        except Exception:
            log("cached file corrupt, re-downloading", dest)
            os.remove(dest)
    last = None
    for attempt in range(1, retries + 1):
        try:
            log(f"downloading (attempt {attempt})", url)
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 biomate-antitnf-demo"})
            with urllib.request.urlopen(req, timeout=600) as r, open(dest, "wb") as f:
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    f.write(chunk)
            # verify gzip integrity end-to-end
            with gzip.open(dest, "rb") as g:
                while g.read(1 << 20):
                    pass
            log("saved", dest, os.path.getsize(dest), "bytes")
            return dest
        except Exception as e:
            last = e
            log("download error:", repr(e), "-> retry")
            if os.path.exists(dest):
                os.remove(dest)
            time.sleep(3 * attempt)
    raise RuntimeError(f"download failed after {retries} attempts: {url}: {last}")

# ---------------------------------------------------------------------------
def parse_series_matrix(path):
    """Return (expr_df [probes x samples], meta_dict). Handles gzip series_matrix."""
    with gzip.open(path, "rt", errors="replace") as f:
        lines = f.readlines()
    meta = {}
    sample_titles = None
    sample_geo = None
    char_lines = []
    data_start = None
    for i, ln in enumerate(lines):
        if ln.startswith("!Sample_title"):
            sample_titles = [x.strip().strip('"') for x in ln.rstrip("\n").split("\t")[1:]]
        elif ln.startswith("!Sample_geo_accession"):
            sample_geo = [x.strip().strip('"') for x in ln.rstrip("\n").split("\t")[1:]]
        elif ln.startswith("!Sample_characteristics_ch1"):
            char_lines.append([x.strip().strip('"') for x in ln.rstrip("\n").split("\t")[1:]])
        elif ln.startswith("!series_matrix_table_begin"):
            data_start = i + 1
            break
    # read expression table
    tbl_lines = []
    for ln in lines[data_start:]:
        if ln.startswith("!series_matrix_table_end"):
            break
        tbl_lines.append(ln)
    expr = pd.read_csv(io.StringIO("".join(tbl_lines)), sep="\t", index_col=0)
    expr.columns = [c.strip().strip('"') for c in expr.columns]
    expr = expr.apply(pd.to_numeric, errors="coerce")
    meta = {
        "titles": sample_titles,
        "geo": sample_geo,
        "characteristics": char_lines,
    }
    return expr, meta

# ---------------------------------------------------------------------------
def _char_field(cvals_list, key):
    """Find 'key: value' among a sample's characteristic strings; return value or None."""
    for c in cvals_list:
        if c.lower().startswith(key.lower() + ":"):
            return c.split(":", 1)[1].strip()
    return None

def label_samples(gse, meta, expr_cols):
    """
    Return DataFrame indexed by GSM with columns: title, disease, response(0/1), timepoint, chars.
    Uses the EXACT GEO characteristic fields (verified from series_matrix), not fragile regex:

      GSE16879 / GSE14580 (Arijs/Leuven): fields
        'disease' (Control/UC/CD), 'response to infliximab' (Yes/No/Not applicable),
        'before or after first infliximab treatment' (Before.../After.../Not applicable)
        + title tokens like UCR1_beforeT / CDcNR5_afterT as cross-check.
      GSE12251 (ACT1): single characteristic 'WK8RSPHM: Yes/No' (week-8 response,
        histologic+mucosal healing). Titles are P#/dose/W0 -> ALL pre-treatment, UC.
    """
    geo = meta["geo"]; titles = meta["titles"]
    chars = meta["characteristics"]
    n = len(geo)
    rows = []
    for i in range(n):
        gsm = geo[i]
        title = titles[i] if titles and i < len(titles) else ""
        cvals_list = [ch[i] for ch in chars if i < len(ch)]
        cvals = " || ".join(cvals_list)

        disease = None; response = None; timepoint = None

        # ---- explicit-field path (GSE16879, GSE14580) ----
        d = _char_field(cvals_list, "disease")
        if d is not None:
            dl = d.lower()
            if "control" in dl: disease = "control"
            elif dl == "uc" or "ulcerative" in dl: disease = "UC"
            elif dl.startswith("cd") or "crohn" in dl: disease = "CD"
            else: disease = d
        r = _char_field(cvals_list, "response to infliximab")
        if r is not None:
            rl = r.lower()
            if rl == "yes": response = 1
            elif rl == "no": response = 0
            else: response = None  # 'Not applicable'
        tp = _char_field(cvals_list, "before or after first infliximab treatment")
        if tp is not None:
            tl = tp.lower()
            if tl.startswith("before"): timepoint = "pre"
            elif tl.startswith("after"): timepoint = "post"
            else: timepoint = None

        # ---- title cross-check / fill for Arijs sets ----
        m = re.match(r"^(UC|CDc|CDi|CD)(NR|R)\d+_(before|after)T", title)
        if m:
            if disease is None:
                disease = "UC" if m.group(1) == "UC" else "CD"
            tresp = 0 if m.group(2) == "NR" else 1
            if response is None: response = tresp
            ttp = "pre" if m.group(3) == "before" else "post"
            if timepoint is None: timepoint = ttp
        if re.match(r"^CO\d+$", title):  # control samples in Arijs sets
            if disease is None: disease = "control"

        # ---- GSE12251 (ACT1): WK8RSPHM field; all arrays are W0 pre-treatment, UC ----
        wk = _char_field(cvals_list, "WK8RSPHM")
        if wk is not None:
            if wk.lower() == "yes": response = 1
            elif wk.lower() == "no": response = 0
            disease = "UC"
            timepoint = "pre"   # titles are P#/dose/W0

        rows.append(dict(gsm=gsm, title=title, disease=disease, response=response,
                         timepoint=timepoint, chars=cvals))
    df = pd.DataFrame(rows).set_index("gsm")
    df = df.loc[[g for g in df.index if g in set(expr_cols)]]
    return df

# ---------------------------------------------------------------------------
def load_gpl570_map(path):
    """probe -> gene symbol from GPL570.annot.gz"""
    with gzip.open(path, "rt", errors="replace") as f:
        lines = f.readlines()
    # find header
    hdr_idx = None
    for i, ln in enumerate(lines):
        if ln.startswith("ID\t") or ln.split("\t")[0].strip() == "ID":
            hdr_idx = i; break
    if hdr_idx is None:
        raise RuntimeError("GPL570 annot header not found")
    df = pd.read_csv(io.StringIO("".join(lines[hdr_idx:])), sep="\t", low_memory=False)
    sym_col = None
    for c in df.columns:
        if c.strip().lower() in ("gene symbol", "gene_symbol", "symbol"):
            sym_col = c; break
    if sym_col is None:
        raise RuntimeError(f"no gene symbol col in GPL570 annot: {list(df.columns)[:8]}")
    m = dict(zip(df["ID"].astype(str), df[sym_col].astype(str)))
    return m

def probes_to_genes(expr, probe2gene):
    """Collapse probes to gene symbols (max mean intensity probe per gene)."""
    genes = pd.Series(expr.index.astype(str)).map(probe2gene).values
    tmp = expr.copy()
    tmp["__gene__"] = genes
    tmp = tmp[tmp["__gene__"].notna() & (tmp["__gene__"] != "") & (tmp["__gene__"] != "---")]
    # collapse: for each gene keep probe with max mean expression
    tmp["__mean__"] = expr.loc[tmp.index].mean(axis=1).values
    tmp = tmp.sort_values("__mean__", ascending=False).drop_duplicates("__gene__")
    g = tmp.set_index("__gene__").drop(columns=["__mean__"])
    return g  # genes x samples

# ---------------------------------------------------------------------------
# Modeling
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.feature_selection import SelectKBest, f_classif
from sklearn.pipeline import Pipeline
from sklearn.metrics import roc_auc_score, average_precision_score

def make_model(kind, n_features):
    """Small, honest, low-capacity models. No heavy tuning."""
    if kind == "baseline":
        # simplest: single best univariate feature -> logistic. (clinical/expression proxy)
        return Pipeline([
            ("scale", StandardScaler()),
            ("sel", SelectKBest(f_classif, k=1)),
            ("clf", LogisticRegression(max_iter=1000, C=1.0)),
        ])
    if kind == "mechanism":
        k = min(20, n_features)
        return Pipeline([
            ("scale", StandardScaler()),
            ("sel", SelectKBest(f_classif, k=k)),
            ("clf", LogisticRegression(max_iter=1000, C=0.5, penalty="l2")),
        ])
    if kind == "full":
        k = min(50, n_features)
        return Pipeline([
            ("scale", StandardScaler()),
            ("sel", SelectKBest(f_classif, k=k)),
            ("clf", LogisticRegression(max_iter=1000, C=0.5, penalty="l2")),
        ])
    raise ValueError(kind)

def loo_predict(X, y, kind):
    """Leave-one-out CV. Feature selection is INSIDE the fold (no leakage). Returns oof probs."""
    n = len(y)
    oof = np.zeros(n)
    for i in range(n):
        tr = np.ones(n, bool); tr[i] = False
        m = make_model(kind, X.shape[1])
        m.fit(X[tr], y[tr])
        oof[i] = m.predict_proba(X[i:i+1])[0, 1]
    return oof

def boot_ci(y, p, metric, n_boot=2000, seed=0):
    rng = np.random.default_rng(seed)
    y = np.asarray(y); p = np.asarray(p)
    n = len(y); stats = []
    for _ in range(n_boot):
        idx = rng.integers(0, n, n)
        if len(np.unique(y[idx])) < 2:
            continue
        stats.append(metric(y[idx], p[idx]))
    if not stats:
        return (np.nan, np.nan, np.nan)
    point = metric(y, p)
    lo, hi = np.percentile(stats, [2.5, 97.5])
    return (point, lo, hi)

def split_conformal_coverage(X, y, kind, alpha=0.10, n_repeat=400, seed=0):
    """
    Proper split-conformal for binary labels using nonconformity = 1 - p_true.
    3-way split per repeat: TRAIN (fit model) / CALIBRATION (out-of-sample nonconformity
    scores) / TEST (evaluate prediction-set coverage). Calibration scores MUST come from
    data not used to fit the model — otherwise in-sample overconfidence breaks the coverage
    guarantee (this is the classic split-conformal exchangeability requirement).
    Report empirical coverage of nominal (1-alpha) prediction sets, averaged over repeats.
    """
    rng = np.random.default_rng(seed)
    n = len(y); covs = []
    for _ in range(n_repeat):
        perm = rng.permutation(n)
        # ~50% train, ~30% calibration, ~20% test (tiny N -> keep cal >= 6)
        n_tr = max(8, int(round(n * 0.5)))
        n_cal = max(6, int(round(n * 0.3)))
        if n_tr + n_cal >= n:  # ensure a nonempty test set
            n_tr = max(6, n - n_cal - 4)
        tr = perm[:n_tr]
        cal = perm[n_tr:n_tr + n_cal]
        tst = perm[n_tr + n_cal:]
        if len(tst) == 0 or len(np.unique(y[tr])) < 2:
            continue
        m = make_model(kind, X.shape[1]); m.fit(X[tr], y[tr])
        # nonconformity scores on OUT-OF-SAMPLE calibration split
        pc = m.predict_proba(X[cal])
        s_cal = 1 - pc[np.arange(len(cal)), y[cal]]
        # conformal quantile with finite-sample correction
        q_level = min(1.0, np.ceil((len(cal) + 1) * (1 - alpha)) / len(cal))
        qhat = np.quantile(s_cal, q_level)
        pt = m.predict_proba(X[tst])
        covered = 0
        for j, ti in enumerate(tst):
            pred_set = [c for c in (0, 1) if (1 - pt[j, c]) <= qhat]
            if y[ti] in pred_set:
                covered += 1
        covs.append(covered / len(tst))
    return float(np.mean(covs)) if covs else np.nan, float(np.std(covs)) if covs else np.nan

# ---------------------------------------------------------------------------
def build_matrix(gse, workdir):
    mpath = download(GEO_MATRIX[gse], os.path.join(workdir, f"{gse}_matrix.txt.gz"))
    expr, meta = parse_series_matrix(mpath)
    labels = label_samples(gse, meta, expr.columns)
    return expr, labels

def main(smoke=False):
    work = OUT
    log("workdir", work, "smoke=", smoke)

    # annotation
    annot_path = download(GPL570_ANNOT, os.path.join(work, "GPL570.annot.gz"))
    probe2gene = load_gpl570_map(annot_path)
    log("GPL570 probes mapped:", len(probe2gene))

    datasets = {}
    for gse in ["GSE12251", "GSE14580", "GSE16879"]:
        expr, labels = build_matrix(gse, work)
        gexpr = probes_to_genes(expr, probe2gene)
        datasets[gse] = (gexpr, labels)
        log(gse, "expr genes x samples:", gexpr.shape, "labeled samples:", len(labels))
        # diagnostics on labels
        pre = labels[labels.timepoint == "pre"]
        log(gse, "pre-treatment samples:", len(pre),
            "responders:", int((pre.response == 1).sum()),
            "non-responders:", int((pre.response == 0).sum()),
            "unknown-resp:", int(pre.response.isna().sum()))
        log(gse, "disease breakdown (pre):", pre.disease.value_counts(dropna=False).to_dict())
        if smoke:
            # write label audit and stop after first dataset in smoke mode
            labels.to_csv(os.path.join(work, f"{gse}_labels.csv"))
            log("SMOKE: label audit written for", gse)

    # write full label audits
    for gse, (gexpr, labels) in datasets.items():
        labels.to_csv(os.path.join(work, f"{gse}_labels.csv"))

    if smoke:
        log("SMOKE COMPLETE — labels parsed, expression loaded, gene mapping OK.")
        return

    # ---- Build per-dataset baseline cohorts: UC pre-treatment with known response ----
    results = {"per_dataset": {}, "cross_dataset": {}, "conformal": {}, "counts": {}}

    def cohort(gse, disease_filter=("UC",)):
        gexpr, labels = datasets[gse]
        sel = labels[(labels.timepoint == "pre") & (labels.response.notna())]
        if disease_filter:
            sel = sel[sel.disease.isin(disease_filter)]
        gsms = [g for g in sel.index if g in gexpr.columns]
        y = sel.loc[gsms, "response"].astype(int).values
        Xg = gexpr[gsms].T  # samples x genes
        return Xg, y, sel.loc[gsms]

    common_mech = None
    per_ds_matrices = {}
    for gse in ["GSE12251", "GSE14580", "GSE16879"]:
        Xg, y, sel = cohort(gse)
        results["counts"][gse] = dict(n=len(y), responders=int(y.sum()),
                                      non_responders=int((y == 0).sum()),
                                      disease="UC")
        per_ds_matrices[gse] = (Xg, y)
        log(gse, "modeling cohort UC-pre:", Xg.shape, "resp", int(y.sum()), "nonresp", int((y==0).sum()))

    # feature spaces
    def mech_cols(Xg):
        cols = [g for g in Xg.columns if g in set(MECHANISM_GENES)]
        return cols

    # ---- Per-dataset LOO-CV for 3 arms ----
    for gse in ["GSE12251", "GSE14580", "GSE16879"]:
        Xg, y = per_ds_matrices[gse]
        if len(y) < 10 or len(np.unique(y)) < 2:
            log("skip modeling", gse, "insufficient n"); continue
        mcols = mech_cols(Xg)
        Xg = Xg.fillna(Xg.mean())
        arms = {}
        # full: most-variable 2000 genes to keep it tractable
        var = Xg.var().sort_values(ascending=False)
        full_cols = var.index[:2000].tolist()
        for arm, cols, kind in [
            ("mechanism", mcols, "mechanism"),
            ("full", full_cols, "full"),
            ("baseline", full_cols, "baseline"),
        ]:
            Xa = Xg[cols].values
            oof = loo_predict(Xa, y, kind)
            auroc = boot_ci(y, oof, roc_auc_score)
            auprc = boot_ci(y, oof, average_precision_score)
            arms[arm] = dict(n_features=len(cols),
                             auroc=auroc, auprc=auprc,
                             prevalence=float(y.mean()))
            log(f"{gse} {arm}: AUROC {auroc[0]:.3f} [{auroc[1]:.3f},{auroc[2]:.3f}] "
                f"AUPRC {auprc[0]:.3f} [{auprc[1]:.3f},{auprc[2]:.3f}] nfeat={len(cols)}")
        results["per_dataset"][gse] = arms

        # conformal coverage (mechanism arm)
        cov, covsd = split_conformal_coverage(Xg[mcols].values, y, "mechanism", alpha=0.10)
        results["conformal"][gse] = dict(nominal=0.90, empirical=cov, sd=covsd)
        log(f"{gse} conformal 90% empirical coverage: {cov:.3f} (sd {covsd:.3f})")

    # ---- Cross-dataset: train GSE16879 (UC pre) -> test GSE12251 (independent ACT1) ----
    # honest leakage-free transfer. Use common genes.
    def cross(train_gse, test_gse, arm):
        Xtr, ytr = per_ds_matrices[train_gse]
        Xte, yte = per_ds_matrices[test_gse]
        common = [g for g in Xtr.columns if g in set(Xte.columns)]
        if arm == "mechanism":
            common = [g for g in common if g in set(MECHANISM_GENES)]
            kind = "mechanism"
        else:
            # full: top-variance in train among common
            v = Xtr[common].var().sort_values(ascending=False)
            common = v.index[:2000].tolist()
            kind = "full" if arm == "full" else "baseline"
        Xtr2 = Xtr[common].fillna(Xtr[common].mean()).values
        Xte2 = Xte[common].fillna(Xtr[common].mean()).values  # impute test with TRAIN means
        m = make_model(kind, len(common)); m.fit(Xtr2, ytr)
        p = m.predict_proba(Xte2)[:, 1]
        return boot_ci(yte, p, roc_auc_score), boot_ci(yte, p, average_precision_score), len(common)

    for arm in ["mechanism", "full", "baseline"]:
        try:
            au, ap, nf = cross("GSE16879", "GSE12251", arm)
            results["cross_dataset"][f"train16879_test12251_{arm}"] = dict(
                auroc=au, auprc=ap, n_features=nf,
                note="independent cohorts (ACT1 test) — leakage-free")
            log(f"CROSS train16879->test12251 {arm}: AUROC {au[0]:.3f} [{au[1]:.3f},{au[2]:.3f}] nfeat={nf}")
        except Exception as e:
            log("cross failed", arm, e)

    with open(os.path.join(work, "results.json"), "w") as f:
        json.dump(results, f, indent=2, default=float)
    log("RESULTS written", os.path.join(work, "results.json"))
    print("=== RESULTS_JSON_BEGIN ===")
    print(json.dumps(results, indent=2, default=float))
    print("=== RESULTS_JSON_END ===")

if __name__ == "__main__":
    smoke = "--smoke" in sys.argv
    main(smoke=smoke)
