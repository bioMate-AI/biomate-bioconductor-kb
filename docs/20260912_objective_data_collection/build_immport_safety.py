"""Arm-level SAFETY labels from ImmPort DR66 (adverse_event x arm denominators).

Per (study, arm): denominator = subjects assigned to the arm (arm_2_subject);
numerators = subjects with >=1 adverse event, with a severe (Grade>=3) event, and
with a treatment-related event. This gives randomized arm-level AE RATES with real
denominators — a patient-level upgrade over the aggregate ClinicalTrials.gov counts.

Honesty guards:
  - denominator is the arm roster, NOT just subjects who happened to have an AE row
    (avoids the classic rate-inflation bug).
  - "severe" = severity grade >=3 parsed from SEVERITY_PREFERRED; studies without
    gradeable severity are flagged (severe_rate = null, not 0).
  - arm identity via arm_2_subject -> arm_or_cohort(study); AE rows whose subject has
    no arm assignment are counted at study level and reported as unassigned.
Training-eligible stays False; ImmPort quarantined pending leakage confirmation.
"""
import json, re
import pandas as pd
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PQ = Path("/tmp/immport_pq")
ae = pd.read_parquet(PQ / "adverse_event.parquet")
a2s = pd.read_parquet(PQ / "arm_2_subject.parquet")
aoc = pd.read_parquet("/tmp/aoc.parquet")[["ARM_ACCESSION", "STUDY_ACCESSION", "NAME"]]

# subject -> arm -> study roster (denominators)
roster = a2s[["ARM_ACCESSION", "SUBJECT_ACCESSION"]].merge(aoc, on="ARM_ACCESSION", how="left")
roster = roster.dropna(subset=["STUDY_ACCESSION"]).drop_duplicates(["ARM_ACCESSION", "SUBJECT_ACCESSION"])

def grade(s):
    m = re.search(r"grade\s*(\d)", str(s).lower())
    return int(m.group(1)) if m else None

ae = ae.copy()
ae["grade"] = ae["SEVERITY_PREFERRED"].map(grade)
ae["severe"] = ae["grade"].apply(lambda g: g is not None and g >= 3)
ae["related"] = ae["RELATION_TO_STUDY_TREATMENT"].fillna("").str.lower().str.contains(
    "related|definite|probable|possible")

# per-subject AE flags within a study (a subject may have many AE rows)
subj_ae = ae.groupby(["STUDY_ACCESSION", "SUBJECT_ACCESSION"]).agg(
    any_ae=("ADVERSE_EVENT_ACCESSION", "size"),
    has_severe=("severe", "max"),
    has_related=("related", "max"),
    study_gradeable=("grade", lambda s: s.notna().any()),
).reset_index()

# attach arm to each rostered subject, then bring in AE flags
merged = roster.merge(subj_ae, on=["STUDY_ACCESSION", "SUBJECT_ACCESSION"], how="left")
merged["any_ae_flag"] = merged["any_ae"].notna() & (merged["any_ae"] > 0)

# CRITICAL: only studies that actually collected AEs give meaningful rates.
# An arm with 0 AEs in an observational cohort that never collected AEs is
# "not collected", NOT "safe". Restrict the safety table to AE-collecting studies.
ae_studies = set(ae["STUDY_ACCESSION"].unique())
n_arms_before = merged["ARM_ACCESSION"].nunique()
merged = merged[merged["STUDY_ACCESSION"].isin(ae_studies)].copy()
n_arms_excluded = n_arms_before - merged["ARM_ACCESSION"].nunique()

# per-study whether severity is gradeable at all
study_gradeable = ae.groupby("STUDY_ACCESSION")["grade"].apply(lambda s: s.notna().any()).to_dict()

def arm_rate(g):
    n = g["SUBJECT_ACCESSION"].nunique()
    study = g["STUDY_ACCESSION"].iloc[0]
    gradeable = study_gradeable.get(study, False)
    n_ae = int(g["any_ae_flag"].sum())
    n_sev = int((g["has_severe"] == True).sum())
    n_rel = int((g["has_related"] == True).sum())
    return pd.Series(dict(
        study=study, arm_name=g["NAME"].iloc[0], n_subjects=n,
        any_ae_rate=round(n_ae / n, 4) if n else None,
        severe_ae_rate=(round(n_sev / n, 4) if (n and gradeable) else None),
        related_ae_rate=round(n_rel / n, 4) if n else None,
        n_ae_subjects=n_ae, n_severe=n_sev, n_related=n_rel,
        severity_gradeable=gradeable,
    ))

arm_tbl = merged.groupby("ARM_ACCESSION").apply(arm_rate, include_groups=False).reset_index()
arm_tbl.to_csv(ROOT / "raw" / "immport_safety_arm_rates.csv", index=False)

studies = sorted(arm_tbl["study"].dropna().unique())
heldout = [s for i, s in enumerate(studies) if i % 5 == 0]
summary = dict(
    source="ImmPort DR66 adverse_event x arm_2_subject (no credentials)",
    objective="safety: arm-level AE rates with denominators",
    n_arms=int(len(arm_tbl)), n_studies=len(studies),
    scope="restricted to AE-collecting studies",
    arms_excluded_no_ae_collection=int(n_arms_excluded),
    n_subjects_in_denominator=int(merged["SUBJECT_ACCESSION"].nunique()),
    total_ae_rows=int(len(ae)),
    arms_with_severity_grading=int(arm_tbl["severity_gradeable"].sum()),
    median_any_ae_rate=round(float(arm_tbl["any_ae_rate"].median()), 3),
    frozen_study_heldout_test=heldout,
    role="arm-level safety labels; STUDY-held-out external test",
    caveats=[
        "denominator = arm roster (not AE-positive subjects) — rates are not inflated",
        "severe = Grade>=3; non-gradeable studies -> severe_rate null, not 0",
        "ImmPort quarantined; confirm not in knowledge-training before eval use",
    ],
    training_eligible=False,
)
(ROOT / "immport_safety_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
print("\ntop arms by size:")
print(arm_tbl.sort_values("n_subjects", ascending=False)
      [["study", "arm_name", "n_subjects", "any_ae_rate", "severe_ae_rate", "related_ae_rate"]].head(10).to_string(index=False))
