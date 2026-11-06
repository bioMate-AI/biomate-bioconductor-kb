"""Extract sample-level labels from downloaded GEO SOFT records.

Produces a per-sample table (patient, timepoint, treatment, response, tissue)
and a per-cohort summary with paired-sample counts and a PROPOSED
patient-held-out split. Nothing here is promoted to training-eligible:
labels still require the matched expression matrix to be joined and a human
sign-off (see AUDIT admission criteria). This only structures what the SOFT
metadata already asserts.
"""
import json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"

def parse_samples(path):
    cur = title = None
    chars = {}
    out = []
    for line in path.open(encoding="utf-8", errors="replace"):
        if line.startswith("^SAMPLE = "):
            if cur:
                out.append((cur, title, chars))
            cur = line.strip().split(" = ", 1)[1]
            title = None
            chars = {}
        elif line.startswith("!Sample_title = "):
            title = line.split(" = ", 1)[1].strip()
        elif line.startswith("!Sample_characteristics_ch1 = "):
            val = line.split(" = ", 1)[1].strip()
            if ":" in val:
                k, v = val.split(":", 1)
                chars[k.strip().lower()] = v.strip()
    if cur:
        out.append((cur, title, chars))
    return out

def derive(gse, gsm, title, chars):
    title = title or ""
    tl = title.lower()
    # patient id
    patient = chars.get("patient")
    if not patient:
        # GSE113156 subject codes e.g. R084 inside "CD8_w0__R084_K9656"
        # (underscores are word chars, so \b won't fire — match on digit run)
        m = re.search(r"R\d{2,4}(?!\d)", title)
        if m:
            patient = m.group(0)
    # timepoint
    timepoint = None
    if re.search(r"w0(?!\d)|week 0|baseline|before", tl):
        timepoint = "pre"
    if re.search(r"w24(?!\d)|week 24|after|on[- ]treatment", tl):
        timepoint = "post"
    treat = chars.get("treatment", "")
    if "before" in treat.lower():
        timepoint = "pre"
    elif "after" in treat.lower():
        timepoint = "post"
    # response label
    response = None
    pheno = chars.get("phenotype", "")
    if "non-responder" in pheno.lower() or "nonresponder" in pheno.lower():
        response = "non_responder"
    elif "responder" in pheno.lower():
        response = "responder"
    return dict(
        gse=gse, gsm=gsm, title=title,
        patient_id=patient,
        timepoint=timepoint,
        treatment=(treat or None),
        response=response,
        tissue=chars.get("tissue"),
        disease=chars.get("disease state") or chars.get("diagnosis"),
        gender=chars.get("gender"),
        age=chars.get("age") or chars.get("age (y)"),
    )

records = []
summary = {}
for path in sorted(RAW.glob("*.soft.txt")):
    gse = path.stem.replace(".soft", "")
    rows = [derive(gse, gsm, title, chars) for gsm, title, chars in parse_samples(path)]
    records.extend(rows)
    patients = {r["patient_id"] for r in rows if r["patient_id"]}
    # paired = a patient with both a pre and a post sample
    paired = set()
    for p in patients:
        tps = {r["timepoint"] for r in rows if r["patient_id"] == p}
        if "pre" in tps and "post" in tps:
            paired.add(p)
    # proposed patient-held-out test split: ~30% of paired patients, deterministic
    ordered = sorted(paired)
    n_test = max(1, round(len(ordered) * 0.3)) if ordered else 0
    held_out = ordered[:n_test]
    summary[gse] = dict(
        n_samples=len(rows),
        n_patients_with_id=len(patients),
        n_paired_pre_post=len(paired),
        n_response_labeled=sum(1 for r in rows if r["response"]),
        n_missing_timepoint=sum(1 for r in rows if not r["timepoint"]),
        proposed_heldout_patients=held_out,
        proposed_split_note=(
            "patient-held-out; all timepoints of a held-out patient stay together"
            if paired else "no paired pre/post patients detected — response-split only"
        ),
    )

(ROOT / "geo_sample_labels.json").write_text(json.dumps(records, indent=2) + "\n")
(ROOT / "geo_label_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
print(f"\n{len(records)} sample records -> geo_sample_labels.json")
