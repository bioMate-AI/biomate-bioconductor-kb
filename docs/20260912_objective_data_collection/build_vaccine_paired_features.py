"""Resolve ImmPort -> GEO/SRA transcriptome bridge for the vaccine-response subjects.

Answers the real question: not "how many titer labels" but "how many subjects have the
model's INPUT modality (a transcriptome) PAIRED with the outcome" — and how many have a
BASELINE (pre-vaccination) transcriptome, which is what actually enables prediction.

Chain: vaccine-response subject -> biosample(subject, study_time) -> expsample_2_biosample
       -> expsample_public_repository(GEO/SRA/dbGaP accession).
GEO+SRA = transcriptome-capable (usable model input). dbGaP = controlled-access genomics
(not a transcriptome, and restricted) -> reported separately, NOT counted as usable input.
Baseline = biosample STUDY_TIME_COLLECTED <= 0 (pre-vaccination).
"""
import json
import pandas as pd
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PQ = Path("/tmp/immport_pq")

vr = pd.read_csv(ROOT / "raw" / "immport_vaccine_response.csv")
vr_subj = set(vr["subject"])

bio = pd.read_parquet(PQ / "biosample.parquet",
                      columns=["BIOSAMPLE_ACCESSION", "SUBJECT_ACCESSION", "STUDY_ACCESSION",
                               "STUDY_TIME_COLLECTED", "STUDY_TIME_COLLECTED_UNIT", "TYPE"])
e2b = pd.read_parquet(PQ / "expsample_2_biosample.parquet")
epr = pd.read_parquet(PQ / "expsample_public_repository.parquet")

# keep only biosamples of vaccine-response subjects
bio = bio[bio["SUBJECT_ACCESSION"].isin(vr_subj)].copy()
bio["t"] = pd.to_numeric(bio["STUDY_TIME_COLLECTED"], errors="coerce")

# biosample -> expsample -> repository
link = (bio.merge(e2b, on="BIOSAMPLE_ACCESSION", how="inner")
           .merge(epr, on="EXPSAMPLE_ACCESSION", how="inner"))
link["repo"] = link["REPOSITORY_NAME"].str.upper()
link["transcriptome_capable"] = link["repo"].isin(["GEO", "SRA", "ENA"])
link["baseline"] = link["t"] <= 0

def subjset(df): return set(df["SUBJECT_ACCESSION"])

usable = link[link["transcriptome_capable"]]
usable_baseline = usable[usable["baseline"]]

summary = {
    "question": "true PAIRED (transcriptome feature, vaccine outcome) N — the trainable set",
    "vaccine_response_subjects_total": len(vr_subj),
    "linked_to_any_public_repo": len(subjset(link)),
    "by_repository": {r: int(link[link["repo"] == r]["SUBJECT_ACCESSION"].nunique())
                      for r in sorted(link["repo"].unique())},
    "transcriptome_capable_GEO_SRA_ENA": {
        "any_timepoint": len(subjset(usable)),
        "BASELINE_pre_vaccination": len(subjset(usable_baseline)),
    },
    "biosample_types_top": link["TYPE"].value_counts().head(8).to_dict(),
    "studies_contributing_paired_baseline": int(usable_baseline["STUDY_ACCESSION"].nunique()),
    "top_studies_by_paired_baseline_subjects":
        usable_baseline.groupby("STUDY_ACCESSION")["SUBJECT_ACCESSION"].nunique()
        .sort_values(ascending=False).head(10).to_dict(),
    "interpretation": (
        "labels: {} subjects; usable model-input pairs (GEO/SRA transcriptome, any time): {}; "
        "with baseline (predictive) transcriptome: {}. The last number is the real trainable N "
        "for 'predict vaccine response from baseline immune state' — everything else is label-only."
    ).format(len(vr_subj), len(subjset(usable)), len(subjset(usable_baseline))),
    "note_dbGaP": "dbGaP links are controlled-access genomics, not transcriptomes — excluded from usable input.",
}
# persist the paired baseline subject/accession map for the actual dataset build
paired = (usable_baseline[["SUBJECT_ACCESSION", "STUDY_ACCESSION", "repo",
                           "REPOSITORY_ACCESSION", "t", "TYPE"]]
          .drop_duplicates().sort_values(["STUDY_ACCESSION", "SUBJECT_ACCESSION"]))
paired.to_csv(ROOT / "raw" / "vaccine_paired_baseline_accessions.csv", index=False)
(ROOT / "vaccine_paired_features_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
