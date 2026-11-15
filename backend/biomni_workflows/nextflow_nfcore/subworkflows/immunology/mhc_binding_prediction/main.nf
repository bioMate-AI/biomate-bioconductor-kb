#!/usr/bin/env nextflow
/*
 * immunology/mhc_binding_prediction
 *
 * LICENSE-FREE peptide x MHC class I binding prediction with MHCflurry 2
 * (O'Donnell et al., Cell Systems 2020; open-source, Apache-2.0). This is the
 * no-license alternative to the NetMHCpan / NetMHCIIpan path, which needs the
 * DTU academic tarball that the executor gates (see antigen_resolution's input
 * contract). It feeds the SAME downstream antigen-resolution step: its output
 * CSV carries peptide, hla_allele and a %rank, exactly the columns
 * epitopeprediction/NetMHC would have produced.
 *
 * Fans out ONE PROCESS PER ALLELE so AWS Batch predicts every allele in
 * PARALLEL; each task scores all peptides against its allele. CPU only
 * (MHCflurry is a small Keras/TF ensemble — no GPU).
 *
 * Per allele the process runs MHCflurry's Class1PresentationPredictor and emits,
 * per peptide:
 *   - affinity_nM            predicted binding affinity (nM; lower = stronger)
 *   - affinity_percentile    %rank vs a random-peptide background (the NetMHC
 *                            %rank analogue; strong <= 2, weak <= 10 by the
 *                            Reynisson-2020 convention reused in antigen_resolution)
 *   - presentation_score     combined affinity + antigen-processing score (0..1)
 *   - processing_score       cleavage/processing score (0..1)
 * plus a per-allele summary JSON and a combined predictions CSV. Scores are
 * MHCflurry's own — NEVER fabricated; a peptide MHCflurry cannot score (e.g.
 * length out of 8..15) is written with null fields, and if the tool is absent
 * or produces nothing the task fails (exit 1), it does not invent numbers.
 *
 * CLASS II (HLA-DR/DP/DQ) is OUT OF SCOPE here: MHCflurry 2 is class I only, and
 * there is no mature pip-installable, redistributable (BSD/MIT/Apache) class-II
 * predictor equivalent to NetMHCIIpan. Class-II prediction therefore still
 * requires the gated NetMHCIIpan path. This is a stated gap, not silently
 * covered — see docs/20261109_MHC_BINDING_LICENSE_FREE.md.
 *
 * Inputs (params):
 *   params.peptides   JSON list of peptide strings, e.g. ["SIINFEKL","GILGFVFTL"]
 *   params.alleles    JSON list of class-I alleles -> one parallel task each,
 *                     e.g. ["HLA-A*02:01","HLA-B*07:02"]
 *   params.sample_id  label (metadata only)
 *   params.outdir     output directory (default: 'results')
 *
 * Container: a dedicated MHCflurry image that MUST BE BUILT (it does not yet
 * exist in ECR). Recipe in the doc: micromamba py3.11 + `pip install mhcflurry`
 * + `mhcflurry-downloads fetch models_class1_presentation` baked in (Batch has
 * no reliable network to fetch models at run time). Named biomate/mhcflurry here;
 * build + push before first run, mirroring the MLIP MD image pattern.
 */

nextflow.enable.dsl = 2


// Demo defaults (overridden by BioMate's executor at launch). SIINFEKL is the
// canonical OVA epitope; GILGFVFTL is the influenza M1 HLA-A*02:01 epitope.
params.peptides  = '["GILGFVFTL","SIINFEKL","NLVPMVATV"]'
params.alleles   = '["HLA-A*02:01","HLA-B*07:02"]'
params.sample_id = 'demo_sample'
params.outdir    = 'results'

// %rank thresholds (Reynisson 2020; same convention antigen_resolution consumes)
params.strong_rank = '2.0'   // affinity_percentile <= 2  -> strong binder
params.weak_rank   = '10.0'  // affinity_percentile <= 10 -> weak binder

process PREDICT_ALLELE {
    tag "${allele}"
    label 'process_low'
    publishDir { "${params.outdir}/mhc_binding/${allele.replaceAll('[^A-Za-z0-9]', '_')}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mhcflurry:x86' : 'biomate/mhcflurry:latest'

    input:
    tuple val(allele), val(peptides_json)

    output:
    tuple val(allele), path("predictions.csv"),  emit: predictions
    tuple val(allele), path("summary.json"),      emit: summary
    path "versions.yml",                          emit: versions

    script:
    """
    export ALLELE='${allele}'
    export PEPTIDES_JSON='${peptides_json}'
    export SAMPLE_ID='${params.sample_id}'
    export STRONG_RANK='${params.strong_rank}'
    export WEAK_RANK='${params.weak_rank}'

    python3 << 'PYEOF'
import os, json, sys, csv

allele   = os.environ["ALLELE"].strip()
sample   = os.environ.get("SAMPLE_ID", "sample")
strong_r = float(os.environ.get("STRONG_RANK", "2.0") or 2.0)
weak_r   = float(os.environ.get("WEAK_RANK", "10.0") or 10.0)
try:
    peptides = json.loads(os.environ.get("PEPTIDES_JSON") or "[]")
except Exception as e:
    sys.exit("FATAL: could not parse params.peptides JSON: %s" % e)
peptides = [str(p).strip().upper() for p in peptides if str(p).strip()]
if not allele:
    sys.exit("FATAL: empty allele")
if not peptides:
    sys.exit("FATAL: no peptides supplied")

# MHCflurry only scores 8..15-mers; keep those, record the rest as unscorable
# (null) rather than dropping them silently.
scorable   = [p for p in peptides if 8 <= len(p) <= 15 and p.isalpha()]
unscorable = [p for p in peptides if p not in scorable]

try:
    from mhcflurry import Class1PresentationPredictor
    import mhcflurry as _mf
except Exception as e:
    sys.exit("FATAL: MHCflurry not available in this image (%s). The "
             "biomate/mhcflurry image must be built with `pip install mhcflurry` "
             "and `mhcflurry-downloads fetch models_class1_presentation`." % e)

predictor = Class1PresentationPredictor.load()

rows = []
if scorable:
    try:
        # include_affinity_percentile=True computes the %rank vs a random-peptide background (the
        # NetMHC %rank analogue); without it the affinity_percentile column is absent and no
        # strong/weak binder can be called (a 25 nM A*02:01 binder read as 0 strong binders).
        df = predictor.predict(peptides=scorable, alleles=[allele], verbose=0,
                               include_affinity_percentile=True)
    except Exception as e:
        sys.exit("FATAL: MHCflurry predict failed for allele %s: %s" % (allele, e))

    def col(r, *names):
        for n in names:
            if n in r and r[n] is not None:
                return r[n]
        return None

    for _, r in df.iterrows():
        rr = r.to_dict()
        aff  = col(rr, "affinity")
        pct  = col(rr, "affinity_percentile")
        pres = col(rr, "presentation_score")
        proc = col(rr, "processing_score")
        pctf = float(pct) if pct is not None else None
        binder = None
        if pctf is not None:
            binder = "strong" if pctf <= strong_r else ("weak" if pctf <= weak_r else "none")
        rows.append({
            "peptide": col(rr, "peptide"),
            "hla_allele": allele,
            "affinity_nM": round(float(aff), 2) if aff is not None else None,
            "affinity_percentile": round(pctf, 4) if pctf is not None else None,
            "presentation_score": round(float(pres), 4) if pres is not None else None,
            "processing_score": round(float(proc), 4) if proc is not None else None,
            "binder": binder,
        })

for p in unscorable:
    rows.append({"peptide": p, "hla_allele": allele, "affinity_nM": None,
                 "affinity_percentile": None, "presentation_score": None,
                 "processing_score": None, "binder": None})

if not rows:
    sys.exit("FATAL: MHCflurry produced no predictions for allele %s" % allele)

cols = ["peptide", "hla_allele", "affinity_nM", "affinity_percentile",
        "presentation_score", "processing_score", "binder"]
with open("predictions.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for r in rows:
        w.writerow(r)

n_strong = sum(1 for r in rows if r["binder"] == "strong")
n_weak   = sum(1 for r in rows if r["binder"] == "weak")
summary = {
    "sample_id": sample,
    "allele": allele,
    "tool": "MHCflurry 2",
    "tool_version": getattr(_mf, "__version__", "unknown"),
    "mhc_class": "I",
    "n_peptides": len(peptides),
    "n_scored": sum(1 for r in rows if r["affinity_percentile"] is not None),
    "n_unscorable": len(unscorable),
    "n_strong_binders": n_strong,
    "n_weak_binders": n_weak,
    "strong_rank_threshold": strong_r,
    "weak_rank_threshold": weak_r,
    "status": "ok",
    "note": "MHCflurry 2 class-I presentation predictor; affinity in nM, "
            "%rank = affinity_percentile. Class II (DR/DP/DQ) not covered by "
            "MHCflurry; use the gated NetMHCIIpan path for class II.",
}
with open("summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps(summary, indent=2))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mhcflurry: \$(python3 -c "import mhcflurry; print(getattr(mhcflurry,'__version__','unknown'))" 2>/dev/null || echo unknown)
        python: \$(python3 --version | cut -d' ' -f2)
    END_VERSIONS
    """
}

process MERGE_PREDICTIONS {
    tag "${params.sample_id}"
    label 'process_low'
    publishDir { "${params.outdir}/mhc_binding" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mhcflurry:x86' : 'biomate/mhcflurry:latest'

    input:
    path "pred_*.csv"

    output:
    path "mhc_binding_predictions.csv", emit: merged
    path "mhc_binding_summary.json",    emit: summary

    script:
    """
    python3 << 'PYEOF'
import csv, glob, json

files = sorted(glob.glob("pred_*.csv"))
cols = ["peptide", "hla_allele", "affinity_nM", "affinity_percentile",
        "presentation_score", "processing_score", "binder"]
rows = []
for f in files:
    with open(f, newline="") as fh:
        for r in csv.DictReader(fh):
            rows.append(r)

with open("mhc_binding_predictions.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for r in rows:
        w.writerow({k: r.get(k) for k in cols})

def _f(v):
    try:
        return float(v)
    except Exception:
        return None

strong = [r for r in rows if r.get("binder") == "strong"]
strong_sorted = sorted(
    strong,
    key=lambda r: (_f(r.get("affinity_percentile")) if _f(r.get("affinity_percentile")) is not None else 1e9),
)
summary = {
    "tool": "MHCflurry 2",
    "mhc_class": "I",
    "n_predictions": len(rows),
    "n_alleles": len({r.get("hla_allele") for r in rows}),
    "n_strong_binders": len(strong),
    "top_strong_binders": [
        {"peptide": r.get("peptide"), "hla_allele": r.get("hla_allele"),
         "affinity_nM": r.get("affinity_nM"), "affinity_percentile": r.get("affinity_percentile")}
        for r in strong_sorted[:20]
    ],
    "status": "ok" if rows else "no_predictions",
    "note": "License-free class-I binding via MHCflurry 2; drop-in for the "
            "NetMHC %rank columns consumed by immunology/antigen_resolution.",
}
with open("mhc_binding_summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps({k: summary[k] for k in ("n_predictions", "n_alleles", "n_strong_binders", "status")}, indent=2))
PYEOF
    """
}

workflow MHC_BINDING_PREDICTION {
    take:
    ch_alleles   // channel: tuple(allele, peptides_json) — ONE element per allele -> parallel

    main:
    PREDICT_ALLELE(ch_alleles)
    MERGE_PREDICTIONS(PREDICT_ALLELE.out.predictions.map { allele, csv -> csv }.collect())

    emit:
    per_allele = PREDICT_ALLELE.out.predictions
    summary    = PREDICT_ALLELE.out.summary
    merged     = MERGE_PREDICTIONS.out.merged
    merged_summary = MERGE_PREDICTIONS.out.summary
    versions   = PREDICT_ALLELE.out.versions
}

// Entry workflow for standalone execution.
workflow {
    def alleles  = params.alleles instanceof String
        ? new groovy.json.JsonSlurper().parseText(params.alleles)
        : params.alleles
    // Pass the peptide JSON string unchanged to every allele task so each scores
    // the full peptide set against its own allele (fan-out parallelism).
    def peptides_json = params.peptides instanceof String
        ? params.peptides
        : groovy.json.JsonOutput.toJson(params.peptides)

    ch_alleles = Channel
        .fromList(alleles)
        .map { a -> tuple(a as String, peptides_json as String) }

    MHC_BINDING_PREDICTION(ch_alleles)

    MHC_BINDING_PREDICTION.out.summary.view { allele, f -> "mhc binding done: ${allele}" }
}
