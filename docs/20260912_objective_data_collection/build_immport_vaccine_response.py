"""Build a measured VACCINE IMMUNE-RESPONSE label set from the ImmPort DR66 corpus.

Uses the relational tables already staged in S3 (no credentials): HAI + neutralizing
antibody titers joined to subject/arm/timepoint. Per (study, subject, strain) we take
the baseline (earliest timepoint) and the peak post-baseline titer, then compute:
  - fold_change = post / pre        (unit-consistent WITHIN a subject/strain series)
  - seroconversion = fold_change>=4 (classic flu endpoint; ONLY for raw-titer studies)
  - seroprotection = post>=40       (HAI; ONLY for raw-titer studies)

Honesty guards (the "units are not labels" trap is real here):
  - Titer scale differs by study (some report raw reciprocal titers up to 1000s, some
    report log-transformed values ~1-15). fold_change is computed within-series so it's
    valid regardless; but the >=4-fold / >=40 rules assume RAW titers, so we FLAG each
    study's scale and only apply those rules where scale looks raw.
  - Requires >=1 pre and >=1 post sample; single-timepoint subjects are dropped, counted.

Output: per-subject response table (raw/, gitignored) + per-study summary + study-held-out
split proposal (docs). Training-eligible stays False; ImmPort quarantined pending leakage
confirmation (verified not wired into training, but knowledge integration is incomplete).
"""
import json
import numpy as np
import pandas as pd
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PQ = Path("/tmp/immport_pq")          # hai_result.parquet, neut_ab_titer_result.parquet
AOC = Path("/tmp/aoc.parquet")        # arm_or_cohort (vaccine identity)

arm = pd.read_parquet(AOC)[["ARM_ACCESSION", "NAME", "DESCRIPTION", "STUDY_ACCESSION"]]
arm = arm.rename(columns={"NAME": "ARM_NAME", "DESCRIPTION": "ARM_DESC"})

def scale_of(values):
    """Heuristic: raw reciprocal titers reach into the 100s-1000s; log-transformed stay small."""
    v = pd.to_numeric(values, errors="coerce").dropna()
    if len(v) == 0:
        return "unknown"
    return "raw_titer" if v.max() >= 40 else "log_or_index"

def build(assay_file, assay):
    df = pd.read_parquet(PQ / assay_file)
    df["t"] = pd.to_numeric(df["STUDY_TIME_COLLECTED"], errors="coerce")
    df["val"] = pd.to_numeric(df["VALUE_PREFERRED"], errors="coerce")
    df = df.dropna(subset=["t", "val", "SUBJECT_ACCESSION"])
    df["strain"] = df["VIRUS_STRAIN_PREFERRED"].fillna(df["VIRUS_STRAIN_REPORTED"]).fillna("NA")
    # per-study scale flag
    scale = {s: scale_of(g["val"]) for s, g in df.groupby("STUDY_ACCESSION")}
    rows, dropped_single = [], 0
    key = ["STUDY_ACCESSION", "SUBJECT_ACCESSION", "ARM_ACCESSION", "strain"]
    for (study, subj, armacc, strain), g in df.groupby(key):
        tmin = g["t"].min()
        pre_vals = g[g["t"] == tmin]["val"]
        post = g[g["t"] > tmin]
        if len(post) == 0 or len(pre_vals) == 0:
            dropped_single += 1
            continue
        pre = float(pre_vals.mean())
        # peak post-baseline titer (robust across day-21/28/30 designs) + nearest-day-28
        peak = float(post["val"].max())
        near28 = post.iloc[(post["t"] - 28).abs().argmin()]
        raw = scale[study] == "raw_titer"
        fc = peak / pre if pre > 0 else np.nan
        rows.append(dict(
            assay=assay, study=study, subject=subj, arm=armacc, strain=strain,
            scale=scale[study], pre_time=float(tmin), pre_titer=pre,
            peak_post_titer=peak, day28_time=float(near28["t"]), day28_titer=float(near28["val"]),
            fold_change=round(fc, 3) if pd.notna(fc) else None,
            seroconversion=(bool(fc >= 4) if (raw and pd.notna(fc)) else None),
            seroprotection=(bool(peak >= 40) if raw else None),
        ))
    return pd.DataFrame(rows), dropped_single, scale

frames, meta = [], {}
for f, a in [("hai_result.parquet", "HAI"), ("neut_ab_titer_result.parquet", "neutAb")]:
    tbl, dropped, scale = build(f, a)
    frames.append(tbl)
    meta[a] = dict(response_rows=len(tbl), dropped_single_timepoint=dropped,
                   studies=int(tbl["study"].nunique()) if len(tbl) else 0)

resp = pd.concat(frames, ignore_index=True)
resp = resp.merge(arm[["ARM_ACCESSION", "ARM_NAME"]], left_on="arm", right_on="ARM_ACCESSION", how="left").drop(columns=["ARM_ACCESSION"])
resp.to_csv(ROOT / "raw" / "immport_vaccine_response.csv", index=False)

# per-study summary + study-held-out split (deterministic: every 5th study by sorted id)
per_study = (resp.groupby(["assay", "study", "scale"])
             .agg(subjects=("subject", "nunique"), strains=("strain", "nunique"),
                  response_rows=("fold_change", "size"),
                  median_fold_change=("fold_change", "median"),
                  seroconversion_rate=("seroconversion", "mean")).reset_index())
raw_studies = sorted(resp[resp["scale"] == "raw_titer"]["study"].unique())
heldout = [s for i, s in enumerate(raw_studies) if i % 5 == 0]

summary = {
    "source": "ImmPort DR66 parquet in S3 (no credentials used)",
    "assays": meta,
    "total_response_rows": len(resp),
    "total_subjects": int(resp["subject"].nunique()),
    "total_studies": int(resp["study"].nunique()),
    "raw_titer_studies": len(raw_studies),
    "log_or_index_studies": int(resp[resp["scale"] == "log_or_index"]["study"].nunique()),
    "usable_seroconversion_rows": int(resp["seroconversion"].notna().sum()),
    "frozen_study_heldout_test": heldout,
    "endpoints": {
        "fold_change": "post_peak/pre; valid within-series regardless of scale",
        "seroconversion": ">=4-fold; RAW-titer studies only",
        "seroprotection": "peak>=40; RAW-titer studies only",
    },
    "caveats": [
        "titer scale differs by study; >=4-fold/>=40 rules applied ONLY to raw-titer studies",
        "peak-post used as response; day-28-nearest also recorded for design-consistent reanalysis",
        "quarantined: ImmPort not wired into training but knowledge integration incomplete — confirm before eval use",
    ],
    "training_eligible": False,
}
(ROOT / "immport_vaccine_response_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
per_study.to_csv(ROOT / "immport_vaccine_response_by_study.csv", index=False)
print(json.dumps(summary, indent=2))
print("\nper-study (top 12 by subjects):")
print(per_study.sort_values("subjects", ascending=False).head(12).to_string(index=False))
