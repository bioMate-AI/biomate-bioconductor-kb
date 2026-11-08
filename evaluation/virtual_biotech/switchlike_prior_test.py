#!/usr/bin/env python3
"""Does cell-type specificity ("switch-like" expression) of a drug's target predict clinical progression?
Replication-style test of the Virtual Biotech claim (Zhang & Zou, Science 2026: +40% Phase1->2, +48% to market) on
BioMate's own inputs: ClinicalTrials.gov full registry (mirrored to S3), Open Targets drug->target, HPA single-cell RNA.

PRE-SPECIFIED (fixed before looking at any result):
  unit      = drug (parent CHEMBL id) with >=1 Phase 1 trial whose start date <= --max-start (default 2016-12-31, >=10y follow-up)
  exposure  = target specificity tau of the drug's target gene across HPA single-cell types; HIGH = top quartile of tau among
              the analysed targets (only genes with max nCPM >= 1). Drugs with several targets use the max tau.
  outcomes  = O1 has a Phase 2+ trial (lowest listed phase >=2, so Phase 1/2 alone does not count); O2 has a Phase 3+ trial; O3 approved (Open Targets maximumClinicalStage == APPROVAL)
  estimate  = risk ratio HIGH vs LOW, 95% CI by bootstrap resampling TARGETS (clusters); adjusted OR from logistic regression with
              drug type, Phase-1 start year and number of Phase-1 trials; shuffled-tau control (targets' tau permuted, 1000x).
  Not tuned afterwards. Secondary (labelled secondary): HPA-style enriched flag, tau as continuous.
Matching is exact on normalised names; the mapping rate is reported. Read the caveats in the output before quoting anything.
"""
import glob, gzip, io, json, os, re, subprocess, sys, zipfile, urllib.request
import numpy as np, pandas as pd

OUT = sys.argv[1] if len(sys.argv) > 1 else "/root/work"
S3_CTG = "s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/clinicaltrials_gov/20261030/"
OT = "https://ftp.ebi.ac.uk/pub/databases/opentargets/platform/26.09/output"
MAX_START = "2016-12-31"
rng = np.random.default_rng(7)
os.makedirs(OUT, exist_ok=True)
log = lambda *a: print(*a, flush=True)


def dl(url, path):
    if not os.path.exists(path):
        urllib.request.urlretrieve(url, path)
    return path


def norm(s):
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", (s or "").lower())
    s = re.sub(r"\b\d+(\.\d+)?\s*(mg|mcg|ug|g|ml|iu|%|mg/kg|mg/m2)\b", " ", s)
    s = re.sub(r"\b(tablet|tablets|capsule|capsules|injection|oral|placebo|infusion|intravenous|iv|dose|doses|solution|cream)\b", " ", s)
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


# ---- Open Targets: names -> parent CHEMBL id, drug -> targets, target ensembl -> symbol
log("OT tables")
dm = pd.read_parquet(dl(OT + "/drug_molecule/00000000.parquet", OUT + "/dm.parquet"), columns=["id", "name", "drugType", "parentId", "synonyms", "tradeNames", "maximumClinicalStage"])
moa = pd.read_parquet(dl(OT + "/drug_mechanism_of_action/00000000.parquet", OUT + "/moa.parquet"), columns=["chemblIds", "targets", "targetType"])
name2id = {}
for r in dm.itertuples():
    pid = r.parentId if r.parentId else r.id
    labels = [r.name] + [x["label"] for x in (r.synonyms if r.synonyms is not None else [])] + [x["label"] for x in (r.tradeNames if r.tradeNames is not None else [])]
    for l in labels:
        k = norm(l)
        if len(k) >= 4:
            name2id.setdefault(k, set()).add(pid)
name2id = {k: next(iter(v)) for k, v in name2id.items() if len(v) == 1}          # drop ambiguous names
dinfo = {(r.parentId or r.id): (r.drugType, r.maximumClinicalStage) for r in dm.itertuples()}
d2t = {}
for r in moa.itertuples():
    if r.targetType != "single protein" or r.targets is None:
        continue
    tg = [t for t in r.targets if t]
    for c in r.chemblIds:
        if tg:
            d2t.setdefault(c, set()).update(tg)

# ---- ClinicalTrials.gov: drug -> trials (phase, start)
log("CT.gov parts")
subprocess.check_call(["aws", "s3", "sync", S3_CTG, OUT + "/ctg", "--exclude", "*", "--include", "studies_part_*", "--only-show-errors"])
rows, n_studies, n_int, n_map = [], 0, 0, 0
for p in sorted(glob.glob(OUT + "/ctg/studies_part_*.jsonl.gz")):
    for line in gzip.open(p, "rt"):
        s = json.loads(line); n_studies += 1
        ps = s.get("protocolSection", {})
        phases = ps.get("designModule", {}).get("phases") or []
        ph = [int(m.group(1)) for x in phases for m in [re.match(r"PHASE(\d)", x)] if m]
        if not ph:
            continue
        start = (ps.get("statusModule", {}).get("startDateStruct") or {}).get("date")
        if not start:
            continue
        start = start if len(start) == 10 else start + "-01" if len(start) == 7 else start + "-01-01"
        seen = set()
        for it in ps.get("armsInterventionsModule", {}).get("interventions", []) or []:
            if it.get("type") not in ("DRUG", "BIOLOGICAL"):
                continue
            n_int += 1
            for nm in [it.get("name")] + (it.get("otherNames") or []):
                d = name2id.get(norm(nm or ""))
                if d and d not in seen:
                    seen.add(d); n_map += 1
                    rows.append((d, s["protocolSection"]["identificationModule"]["nctId"], max(ph), min(ph), start))
                    break
log("studies", n_studies, "drug/biologic interventions", n_int, "mapped", n_map, "(%.1f%%)" % (100 * n_map / max(n_int, 1)))
tr = pd.DataFrame(rows, columns=["drug", "nct", "maxph", "minph", "start"]).drop_duplicates(["drug", "nct"])

# ---- unit table
p1 = tr[tr.minph == 1].groupby("drug").agg(first_p1=("start", "min"), n_p1=("nct", "nunique"))
g = tr.groupby("drug").agg(max_phase=("minph", "max"))   # highest LOWEST-listed phase: a Phase 1/2 trial counts as Phase 1, so O1/O2 need a real Phase 2/3+ trial
u = p1.join(g)
u = u[u.first_p1 <= MAX_START].copy()
u["year"] = u.first_p1.str[:4].astype(int)
u["O1"] = (u.max_phase >= 2).astype(int); u["O2"] = (u.max_phase >= 3).astype(int)
u["O3"] = [int(dinfo.get(d, (None, None))[1] == "APPROVAL") for d in u.index]
u["dtyp"] = [dinfo.get(d, ("NA", None))[0] for d in u.index]
u = u[u.index.isin(d2t)].copy()
log("analysed drugs with single-protein target + Phase1 <= %s:" % MAX_START, len(u))

# ---- HPA specificity
log("HPA")
z = dl("https://www.proteinatlas.org/download/tsv/rna_single_cell_type.tsv.zip", OUT + "/hpa.zip")
hpa = pd.read_csv(zipfile.ZipFile(z).open("rna_single_cell_type.tsv"), sep="\t", usecols=["Gene", "Cell type", "nCPM"])
piv = hpa.groupby(["Gene", "Cell type"]).nCPM.mean().unstack(fill_value=0)
mx = piv.max(axis=1)
tau = ((1 - piv.div(mx.replace(0, np.nan), axis=0)).sum(axis=1) / (piv.shape[1] - 1))
enr = (mx >= 1) & (mx / ((piv.sum(axis=1) - mx) / (piv.shape[1] - 1)).replace(0, np.nan) >= 4)
spec = pd.DataFrame({"tau": tau, "enriched": enr.fillna(False)})[mx >= 1]
def _tau(d):
    v = [spec.tau[t] for t in d2t[d] if t in spec.index]      # only targets with an HPA specificity value
    return max(v) if v else np.nan


u["tau"] = [_tau(d) for d in u.index]
u["enr"] = [int(any(bool(spec.enriched[t]) for t in d2t[d] if t in spec.index)) for d in u.index]
u["target"] = [sorted(d2t[d])[0] for d in u.index]
u = u.dropna(subset=["tau"]).copy()
thr = u.drop_duplicates("target").tau.quantile(0.75)
u["high"] = (u.tau >= thr).astype(int)
log("drugs with HPA specificity:", len(u), "targets:", u.target.nunique(), "tau top-quartile cutoff %.3f" % thr)


def rr(df, o):
    a, b = df[df.high == 1][o], df[df.high == 0][o]
    return (a.mean() / b.mean()) if b.mean() > 0 and len(a) and len(b) else np.nan


def boot(df, o, n=1000):
    ts = df.target.unique(); grp = {t: df[df.target == t] for t in ts}; v = []
    for _ in range(n):
        s = pd.concat([grp[t] for t in rng.choice(ts, len(ts))]); v.append(rr(s, o))
    return np.nanpercentile(v, [2.5, 97.5])


res = {"n_drugs": len(u), "n_targets": int(u.target.nunique()), "mapping_rate_pct": round(100 * n_map / max(n_int, 1), 1),
       "tau_cutoff": float(thr), "outcomes": {}}
import statsmodels.formula.api as smf
for o, lab in (("O1", "reached Phase 2+"), ("O2", "reached Phase 3+"), ("O3", "approved")):
    est = rr(u, o); lo, hi = boot(u, o)
    # shuffled-tau control: permute tau across targets
    tt = u.drop_duplicates("target")[["target", "tau"]]; null = []
    for _ in range(1000):
        m = dict(zip(tt.target, rng.permutation(tt.tau.values))); v = u.copy(); v["high"] = (v.target.map(m) >= thr).astype(int); null.append(rr(v, o))
    adj = None
    try:
        f = smf.logit("%s ~ high + C(dtyp) + year + n_p1" % o, data=u).fit(disp=0, cov_type="cluster", cov_kwds={"groups": pd.factorize(u.target)[0]})
        adj = {"OR": float(np.exp(f.params["high"])), "ci": [float(np.exp(x)) for x in f.conf_int().loc["high"]], "p": float(f.pvalues["high"])}
    except Exception as e:
        adj = {"error": str(e)[:120]}
    res["outcomes"][o] = {"label": lab, "base_rate_low": float(u[u.high == 0][o].mean()), "rate_high": float(u[u.high == 1][o].mean()),
                          "risk_ratio": float(est), "rr_ci95": [float(lo), float(hi)], "shuffled_null_rr_mean": float(np.nanmean(null)),
                          "shuffled_null_p_ge": float(np.mean(np.array(null) >= est)), "adjusted_logit": adj}
    log(o, lab, json.dumps(res["outcomes"][o]))
res["secondary_enriched_flag_rr"] = {o: float(u[u.enr == 1][o].mean() / u[u.enr == 0][o].mean()) if u[u.enr == 0][o].mean() > 0 else None for o in ("O1", "O2", "O3")}
res["caveats"] = ["Drugs are restricted to those in Open Targets (mostly ChEMBL-known), so drugs that failed early and were never curated are under-represented: survivorship bias.",
                  "Exact-name matching only; unmatched interventions are dropped (mapping rate above).",
                  "Correlational. Targets differ by disease area and modality; only drug type, start year and trial count are adjusted.",
                  "HPA single-cell types are healthy-tissue cell types, a proxy for the paper's atlases (CELLxGENE, Tabula Sapiens).",
                  "The paper reports +40% (Phase1->2) and +48% (to market); compare risk ratios only loosely: definitions and data differ."]
json.dump(res, open(OUT + "/switchlike_result.json", "w"), indent=1)
u.reset_index().to_csv(OUT + "/switchlike_units.csv", index=False)
subprocess.check_call(["aws", "s3", "cp", OUT + "/switchlike_result.json", S3_CTG.replace("clinicaltrials_gov/20261030/", "virtual_biotech_test/") + "switchlike_result.json", "--only-show-errors"])
subprocess.check_call(["aws", "s3", "cp", OUT + "/switchlike_units.csv", S3_CTG.replace("clinicaltrials_gov/20261030/", "virtual_biotech_test/") + "switchlike_units.csv", "--only-show-errors"])
log("done")
