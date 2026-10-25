"""Build the clean (domain, peptide, in-cell score, noise) table.

PCA2 (primary): MTX-selection PPI DHFR-PCA, pools P4/P5/P6 = PBD 363/366/385 (all PDZ).
  score  = med_norm  (median over >=2 outlier-filtered replicates of the normalised T2
           selection coefficient; 0 = negative-reference level, 1 = positive-reference level).
  noise  = SD of the kept replicates / sqrt(n_kept) on the same scale (from filtered_coefficient.csv).
  Rows kept: peptides that are mutational variants (singles/doubles) of the three
  designed peptide motifs (families 363/366/385); dropped: 'reference' (unrelated control
  peptides), stray family-246 rows, peptides with a stop codon ('*').
PCA1 (for the 7-domain analysis): med_ppi_score.csv med_norm, cognate family only.
"""
import os, json, collections
import numpy as np, pandas as pd
from common import RAW, OUT_TABLE, DOMAINS, HERE


def wt_of(row):
    """Reconstruct the wild-type motif of a variant row from its (pos, max) annotations."""
    s = list(row.aa_seq)
    for p, mx in ((row.pos1, row.max1), (row.pos2, row.max2), (row.pos, row.max)):
        if pd.notna(p) and isinstance(mx, str) and 1 <= int(p) <= len(s):
            s[int(p) - 1] = mx
    return "".join(s)


def build_pca2():
    m = pd.read_csv(f"{RAW}/PCA2/med_score_filtered.csv")
    m = m[(m.assay == "PPI") & (m.condition == "MTX") & m.pbd.notna() & m.med_norm.notna()].copy()
    m["domain"] = m.pbd.astype(int).astype(str)
    m = m[m.family.isin(["363", "366", "385"]) & ~m.aa_seq.str.contains(r"\*")]
    f = pd.read_csv(f"{RAW}/PCA2/filtered_coefficient.csv", low_memory=False)
    f = f[(f.condition == "MTX") & (f.assay == "PPI") & (f.remove != True)]
    f["domain"] = f.pool.map({"P4": "363", "P5": "366", "P6": "385"})
    # replicate-level value = mean over codon variants within replicate, then SD across replicates
    rep = f.groupby(["domain", "aa_seq", "replicate"]).norm_sel_coef.mean().reset_index()
    g = rep.groupby(["domain", "aa_seq"]).norm_sel_coef.agg(["std", "count"]).reset_index()
    g["se"] = g["std"] / np.sqrt(g["count"])
    m["wt"] = m.apply(wt_of, axis=1)
    t = (m.groupby(["domain", "aa_seq"]).agg(score=("med_norm", "mean"), family=("family", "first"),
         wt=("wt", "first"), n_raw_rows=("med_norm", "size")).reset_index())
    t = t.merge(g[["domain", "aa_seq", "se", "count"]], on=["domain", "aa_seq"], how="left").rename(columns={"count": "n_rep"})
    t["dataset"] = "PCA2"
    return t


def build_pca1():
    a = pd.read_csv(f"{RAW}/PCA1/med_ppi_score.csv")
    a = a[a.family.str.startswith("PRM_") & ~a.aa_seq.str.contains(r"\*") & a.med_norm.notna()].copy()
    a["domain"] = a.family.str.replace("PRM_0", "", regex=False)
    a["family"] = a["domain"]
    a["pos"] = np.nan; a["max"] = np.nan
    a["wt"] = a.apply(wt_of, axis=1)
    t = a.groupby(["domain", "aa_seq"]).agg(score=("med_norm", "mean"), family=("family", "first"), wt=("wt", "first")).reset_index()
    t["se"] = np.nan; t["n_rep"] = np.nan; t["dataset"] = "PCA1"
    return t


def add_variant_info(t):
    bb = {fam: collections.Counter(g.wt).most_common(1)[0][0] for fam, g in t.groupby("family")}
    t["backbone"] = t.family.map(bb)
    t["cognate"] = t.domain == t.family
    t["dclass"] = t.domain.map(lambda d: DOMAINS[d]["cls"])
    t["n_mut"] = [sum(a != b for a, b in zip(p, bbs)) if len(p) == len(bbs) else np.nan
                  for p, bbs in zip(t.aa_seq, t.backbone)]
    return t, bb


def build_all():
    t2 = build_pca2(); t1 = build_pca1()
    t = pd.concat([t1, t2], ignore_index=True)
    t, bb = add_variant_info(t)
    return t, bb


def avail_table():
    """Measured availability (peptide-only DHFR-PCA), domain independent. PCA1 doubles + PCA2 pool P1 singles."""
    a1 = pd.read_csv(f"{RAW}/PCA1/med_avail_score.csv")
    a1 = a1[a1.family.str.startswith("PRM_")][["aa_seq", "med_norm"]]
    m = pd.read_csv(f"{RAW}/PCA2/med_score_filtered.csv")
    a2 = m[(m.assay == "Avail") & (m.pool == "P1") & (m.condition == "MTX")][["aa_seq", "med_norm"]]
    return pd.concat([a1, a2]).groupby("aa_seq").med_norm.mean()


if __name__ == "__main__":
    os.makedirs(OUT_TABLE, exist_ok=True)
    t, bb = build_all()
    t.to_csv(f"{OUT_TABLE}/clean_table.csv", index=False)
    summ = {
        "backbones": bb,
        "n_domains_pca2_ppi_mtx": int(t[t.dataset == "PCA2"].domain.nunique()),
        "n_domains_pca1": int(t[t.dataset == "PCA1"].domain.nunique()),
        "n_domains_union": int(t.domain.nunique()),
        "rows_per_dataset_domain": {f"{k[0]}/{k[1]}": int(v) for k, v in t.groupby(["dataset", "domain"]).size().items()},
        "pca2_rows_per_domain_family": {f"{k[0]}/{k[1]}": int(v) for k, v in t[t.dataset == "PCA2"].groupby(["domain", "family"]).size().items()},
        "pca2_shared_peptides_in_all_3_domains": int((t[t.dataset == "PCA2"].groupby("aa_seq").domain.nunique() == 3).sum()),
        "pca2_median_n_rep": float(t[t.dataset == "PCA2"].n_rep.median()),
        "pca2_median_se": float(t[t.dataset == "PCA2"].se.median()),
        "pca2_score_sd": float(t[t.dataset == "PCA2"].score.std()),
        "domains": {k: dict(cls=v["cls"], gene=v["gene"], uniprot=v["uniprot"], length=len(v["seq"])) for k, v in DOMAINS.items()},
    }
    json.dump(summ, open(f"{HERE}/table_summary.json", "w"), indent=1)
    print(json.dumps(summ, indent=1))
