#!/usr/bin/env nextflow
/*
 * genomics/ebv_cfdna_mrd
 *
 * Plasma EBV DNA / ctDNA MRD quantification for nasopharyngeal-carcinoma (NPC)
 * liquid biopsy. Quantifies EBV (or a generic ctDNA target panel) copies from
 * aligned cell-free DNA reads, estimates copies/mL, computes LoB/LoD (CLSI
 * EP17-A2), and makes a SERIAL-TIMEPOINT MRD call (positive / negative /
 * indeterminate) with a molecular-response trajectory.
 *
 * RUNS WITH NO USER INPUT: the DEMO path uses a small built-in synthetic dataset
 * (params.target_counts) giving, per serial timepoint, the target-region read
 * count + total mapped reads + plasma volume (mL) + a spike-in normalizer, plus
 * blank (NTC / healthy-donor) and low-positive replicate controls so LoB/LoD are
 * computed empirically. NO real BAM is needed for the demo.
 *
 * REAL path (optional): supply params.bam + params.target_bed and the first
 * process counts target-region reads with samtools over the BED, builds a
 * single-timepoint counts record (plasma volume / spike-in from params), and the
 * same quantitation runs. The demo path never touches samtools.
 *
 * ------------------------------------------------------------------------------
 * copies/mL MODEL ASSUMPTIONS (scientifically honest — read-counts alone cannot
 * give absolute copies without a normalizer):
 *   copies/mL = target_copies / plasma_volume_mL
 *   1) SPIKE-IN normalizer (preferred): a known number of spike-in copies yields
 *      a known number of spike reads, so reads_per_copy = spike_reads/spike_copies
 *      and  target_copies = target_reads * spike_copies / spike_reads.
 *   2) GENOME-EQUIVALENT normalizer (fallback, no spike): the total mapped reads
 *      represent the input genome equivalents GE = input_dna_ng * GE_per_ng
 *      (default 303 haploid copies per ng; ~3.3 pg/haploid genome). Then
 *      target_copies = target_reads / (total_mapped_reads / GE).
 *   Both assume UNIFORM capture/mapping efficiency across target and normalizer.
 *   This is NOT a validated clinical quantitation — it is a transparent estimate.
 *
 * LoB / LoD (CLSI EP17-A2, parametric, one-sided 95% => z = 1.645):
 *   LoB = mean(blank copies/mL) + 1.645*SD(blank)        [needs >= 2 blanks, else 0]
 *   LoD = LoB + 1.645*SD(low-positive copies/mL)         [needs >= 2 low-pos, else
 *                                                          the DECLARED assay LoD
 *                                                          params.lod_copies_per_ml]
 * MRD call per timepoint: positive if copies/mL >= LoD; negative if <= LoB;
 * indeterminate in between. No clinical thresholds beyond these documented params
 * are fabricated.
 *
 * Outputs: mrd_report.json (per-timepoint copies/mL, LoB/LoD, MRD call +
 * trajectory + model assumptions), ebv_cfdna_copies.csv, summary.json,
 * qc_metrics.json. The final SUMMARISE process LOUD-FAILS (raise SystemExit) if
 * no timepoint output was produced.
 *
 * Container: a bioconda-based image with samtools + python3 (stdlib only is used
 * here — no pandas/numpy dependency, for robustness). Image = biomate/cfdna
 * (build recipe in the DB-spec annotation: micromamba python3.11 + samtools from
 * bioconda; a public pullable equivalent for the samtools-count step is
 * quay.io/biocontainers/samtools). ECR mirror used on AWS Batch.
 */

nextflow.enable.dsl = 2

// Note: do NOT add `import groovy.json.JsonSlurper` here — unused and rejected as a
// script compile error on some Batch Nextflow heads (same class as antibody_antigen_complex).

// ---- Demo defaults so the workflow runs with NO inputs --------------------
// Synthetic NPC serial-timepoint EBV cfDNA dataset (illustrative, NOT patient
// data). Spike-in normalizer: 5000 spike copies -> 1800 spike reads
// (reads_per_copy = 0.36). Plasma volume 4 mL. A declining EBV MRD trajectory
// with the final surveillance draw landing between LoB and LoD (indeterminate).
params.target_counts = '{"assay":"EBV cfDNA MRD (synthetic demo)","target":"EBV","input_dna_ng":20,"genome_equivalents_per_ng":303,"timepoints":[{"timepoint":"baseline","day":0,"target_reads":5200,"total_mapped_reads":30000000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000},{"timepoint":"post_induction","day":21,"target_reads":820,"total_mapped_reads":29500000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000},{"timepoint":"end_of_treatment","day":120,"target_reads":60,"total_mapped_reads":31000000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000},{"timepoint":"surveillance_m3","day":210,"target_reads":8,"total_mapped_reads":30200000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000}],"blanks":[{"label":"NTC_1","target_reads":2,"total_mapped_reads":28000000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000},{"label":"NTC_2","target_reads":3,"total_mapped_reads":28500000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000},{"label":"healthy_donor_1","target_reads":1,"total_mapped_reads":29000000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000}],"low_positives":[{"label":"LP_1","target_reads":22,"total_mapped_reads":30000000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000},{"label":"LP_2","target_reads":18,"total_mapped_reads":30000000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000},{"label":"LP_3","target_reads":26,"total_mapped_reads":30000000,"plasma_ml":4.0,"spike_reads":1800,"spike_copies":5000}]}'

// Optional real inputs (demo does not need them).
params.bam        = ''     // aligned cfDNA BAM (coordinate-sorted)
params.target_bed = ''     // BED of EBV / ctDNA target regions

// Real-BAM single-timepoint metadata (used only when params.bam is set).
params.plasma_ml    = '4.0'    // plasma volume (mL) extracted for the sample
params.spike_reads  = '0'      // spike-in reads (0 -> use genome-equivalent model)
params.spike_copies = '0'      // spike-in copies added (0 -> genome-equivalent model)

// Assay constants.
params.input_dna_ng           = '20'    // cfDNA input into the library (ng)
params.genome_equivalents_per_ng = '303' // haploid genome copies per ng (~3.3 pg/haploid)
params.lod_copies_per_ml      = '10'    // declared assay LoD (fallback when no low-pos replicates)
params.outdir                 = 'results'

process PREP_COUNTS {
    tag "ebv_cfdna_mrd"
    label 'process_low'
    publishDir { "${params.outdir}/ebv_cfdna_mrd" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    tuple val(bam), val(target_bed), val(counts_json)

    output:
    path "counts.json",  emit: counts
    path "versions.yml", emit: versions

    script:
    """
    export BAM='${bam}'
    export TARGET_BED='${target_bed}'
    export PLASMA_ML='${params.plasma_ml}'
    export SPIKE_READS='${params.spike_reads}'
    export SPIKE_COPIES='${params.spike_copies}'
    export INPUT_DNA_NG='${params.input_dna_ng}'
    export GE_PER_NG='${params.genome_equivalents_per_ng}'
    export TARGET_COUNTS_JSON='${counts_json}'

    HAVE_BAM=0
    if [ -n "\$BAM" ] && [ -f "\$BAM" ]; then
        HAVE_BAM=1
        samtools index "\$BAM" 2>/dev/null || true
        TOTAL=\$(samtools view -c -F 4 "\$BAM")
        echo "\$TOTAL" > total_mapped.txt
        if [ -n "\$TARGET_BED" ] && [ -f "\$TARGET_BED" ]; then
            TREADS=\$(samtools view -c -F 4 -L "\$TARGET_BED" "\$BAM")
        else
            TREADS=0
        fi
        echo "\$TREADS" > target_reads.txt
    fi
    export HAVE_BAM

    python3 << 'PYEOF'
import os, json, sys

have_bam = os.environ.get("HAVE_BAM", "0") == "1"
counts_json = os.environ.get("TARGET_COUNTS_JSON", "") or ""

if have_bam:
    try:
        total = int(open("total_mapped.txt").read().strip() or "0")
    except Exception:
        total = 0
    try:
        treads = int(open("target_reads.txt").read().strip() or "0")
    except Exception:
        treads = 0
    data = {
        "assay": "EBV cfDNA MRD (real BAM, single timepoint)",
        "target": "EBV",
        "input_dna_ng": float(os.environ.get("INPUT_DNA_NG", "20") or 20),
        "genome_equivalents_per_ng": float(os.environ.get("GE_PER_NG", "303") or 303),
        "timepoints": [{
            "timepoint": "sample",
            "day": 0,
            "target_reads": treads,
            "total_mapped_reads": total,
            "plasma_ml": float(os.environ.get("PLASMA_ML", "4.0") or 4.0),
            "spike_reads": float(os.environ.get("SPIKE_READS", "0") or 0),
            "spike_copies": float(os.environ.get("SPIKE_COPIES", "0") or 0),
        }],
        "blanks": [],
        "low_positives": [],
    }
else:
    try:
        data = json.loads(counts_json)
    except Exception as e:
        sys.exit("FATAL: could not parse params.target_counts JSON and no BAM supplied: %s" % e)

tps = data.get("timepoints") or []
if not tps:
    sys.exit("FATAL: no timepoints to quantify (demo JSON empty and no BAM counts).")

with open("counts.json", "w") as fh:
    json.dump(data, fh, indent=2)
print("prepared counts for %d timepoint(s); source=%s" % (len(tps), "bam" if have_bam else "demo_json"))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo unknown)
        python: \$(python3 --version | cut -d' ' -f2)
    END_VERSIONS
    """
}

process QUANTIFY_MRD {
    tag "ebv_cfdna_mrd"
    label 'process_low'
    publishDir { "${params.outdir}/ebv_cfdna_mrd" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path "counts.json"

    output:
    path "mrd_report.json",       emit: report
    path "ebv_cfdna_copies.csv",  emit: copies

    script:
    """
    export LOD_DECLARED='${params.lod_copies_per_ml}'

    python3 << 'PYEOF'
import os, json, csv, math, sys, statistics

try:
    data = json.load(open("counts.json"))
except Exception as e:
    sys.exit("FATAL: cannot read counts.json: %s" % e)

input_dna_ng = float(data.get("input_dna_ng", 20) or 20)
ge_per_ng = float(data.get("genome_equivalents_per_ng", 303) or 303)
lod_declared = float(os.environ.get("LOD_DECLARED", "10") or 10)
PSEUDO = 1.0
Z = 1.645  # CLSI EP17-A2 one-sided 95%

def copies_from_record(rec):
    treads = float(rec.get("target_reads", 0) or 0)
    total = float(rec.get("total_mapped_reads", 0) or 0)
    plasma = float(rec.get("plasma_ml", 0) or 0)
    sreads = float(rec.get("spike_reads", 0) or 0)
    scopies = float(rec.get("spike_copies", 0) or 0)
    if plasma <= 0:
        plasma = 1.0
    if sreads > 0 and scopies > 0:
        rpc = sreads / scopies
        tcop = (treads / rpc) if rpc > 0 else 0.0
        norm = "spike_in"
    elif total > 0 and input_dna_ng > 0 and ge_per_ng > 0:
        ge = input_dna_ng * ge_per_ng
        rpg = total / ge
        tcop = (treads / rpg) if rpg > 0 else 0.0
        norm = "genome_equivalent"
    else:
        tcop = 0.0
        norm = "undetermined"
    return tcop, tcop / plasma, norm, plasma

tps_in = data.get("timepoints") or []
if not tps_in:
    sys.exit("FATAL: no timepoints in counts.json")

blanks = data.get("blanks") or []
lowpos = data.get("low_positives") or []
blank_cpm = [copies_from_record(b)[1] for b in blanks]
lp_cpm = [copies_from_record(l)[1] for l in lowpos]

if len(blank_cpm) >= 2:
    lob = statistics.mean(blank_cpm) + Z * statistics.stdev(blank_cpm)
    lob_source = "empirical_ep17"
else:
    lob = 0.0
    lob_source = "declared_zero_insufficient_blanks"

if len(lp_cpm) >= 2:
    lod = lob + Z * statistics.stdev(lp_cpm)
    lod_source = "empirical_ep17"
else:
    lod = lod_declared
    lod_source = "declared_param"

def mrd_call(cpm):
    if cpm <= lob:
        return "negative"
    if cpm >= lod:
        return "positive"
    return "indeterminate"

rows = []
for rec in tps_in:
    tcop, cpm, norm, plasma = copies_from_record(rec)
    rows.append({
        "timepoint": rec.get("timepoint", "t"),
        "day": rec.get("day"),
        "target_reads": rec.get("target_reads"),
        "total_mapped_reads": rec.get("total_mapped_reads"),
        "plasma_ml": plasma,
        "normalizer": norm,
        "target_copies": round(tcop, 3),
        "copies_per_ml": round(cpm, 3),
        "mrd_call": mrd_call(cpm),
    })

baseline = rows[0]["copies_per_ml"]
for r in rows:
    r["log10_fold_from_baseline"] = round(math.log10((r["copies_per_ml"] + PSEUDO) / (baseline + PSEUDO)), 4)

latest = rows[-1]
if latest["copies_per_ml"] <= lob:
    mol = "complete_molecular_response"
elif latest["log10_fold_from_baseline"] <= -1.0:
    mol = "major_molecular_response"
elif latest["log10_fold_from_baseline"] < -0.3:
    mol = "partial_molecular_response"
elif latest["log10_fold_from_baseline"] > 0.3:
    mol = "molecular_progression"
else:
    mol = "stable"

if latest["copies_per_ml"] < baseline:
    direction = "declining"
elif latest["copies_per_ml"] > baseline:
    direction = "rising"
else:
    direction = "flat"

cols = ["timepoint", "day", "target_reads", "total_mapped_reads", "plasma_ml",
        "normalizer", "target_copies", "copies_per_ml", "mrd_call",
        "log10_fold_from_baseline"]
with open("ebv_cfdna_copies.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for r in rows:
        w.writerow({k: r.get(k) for k in cols})

report = {
    "assay": data.get("assay", "EBV cfDNA MRD"),
    "target": data.get("target", "EBV"),
    "input_dna_ng": input_dna_ng,
    "genome_equivalents_per_ng": ge_per_ng,
    "lob_copies_per_ml": round(lob, 4),
    "lod_copies_per_ml": round(lod, 4),
    "lob_source": lob_source,
    "lod_source": lod_source,
    "n_blanks": len(blanks),
    "n_low_positives": len(lowpos),
    "timepoints": rows,
    "trajectory": {
        "baseline_copies_per_ml": baseline,
        "latest_copies_per_ml": latest["copies_per_ml"],
        "latest_timepoint": latest["timepoint"],
        "direction": direction,
        "overall_mrd_call": latest["mrd_call"],
        "molecular_response": mol,
    },
    "model_assumptions": [
        "copies/mL = target_copies / plasma_volume_mL.",
        "Spike-in normalizer (preferred): target_copies = target_reads * spike_copies / spike_reads (reads-per-copy from a known spiked-in control).",
        "Genome-equivalent normalizer (fallback, no spike): total_mapped_reads represent input genome equivalents GE = input_dna_ng * genome_equivalents_per_ng (default 303 haploid copies/ng); target_copies = target_reads / (total_mapped_reads / GE).",
        "LoB (CLSI EP17-A2) = mean(blank) + 1.645*SD(blank) when >= 2 blank/NTC replicates are supplied, else 0.",
        "LoD = LoB + 1.645*SD(low-positive) when >= 2 low-positive replicates are supplied, else the declared assay LoD (params.lod_copies_per_ml).",
        "MRD call: positive if copies/mL >= LoD; negative if <= LoB; indeterminate in between.",
        "log10 fold from baseline uses a pseudocount of 1 copy/mL to avoid log(0).",
        "Read-count-to-copies conversion assumes uniform capture/mapping efficiency across target and normalizer; it is NOT a validated clinical quantitation.",
    ],
    "status": "ok",
}
with open("mrd_report.json", "w") as fh:
    json.dump(report, fh, indent=2)
print(json.dumps({"n_timepoints": len(rows), "overall_mrd_call": latest["mrd_call"],
                  "lob": round(lob, 3), "lod": round(lod, 3)}, indent=2))
PYEOF
    """
}

process SUMMARISE {
    tag "ebv_cfdna_mrd"
    label 'process_low'
    publishDir { "${params.outdir}/ebv_cfdna_mrd" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path "mrd_report.json"
    path "ebv_cfdna_copies.csv"

    output:
    path "summary.json",     emit: summary
    path "qc_metrics.json",  emit: qc

    script:
    """
    python3 << 'PYEOF'
import json, csv

try:
    rep = json.load(open("mrd_report.json"))
except Exception as e:
    raise SystemExit("FATAL: cannot read mrd_report.json: %s" % e)

tps = rep.get("timepoints") or []
if not tps:
    raise SystemExit("FATAL: MRD report has no timepoints; nothing was quantified.")

try:
    with open("ebv_cfdna_copies.csv") as fh:
        rows = list(csv.DictReader(fh))
except Exception:
    rows = []
if not rows:
    raise SystemExit("FATAL: copies CSV empty; no per-timepoint output produced.")

n_pos = sum(1 for t in tps if t.get("mrd_call") == "positive")
n_neg = sum(1 for t in tps if t.get("mrd_call") == "negative")
n_ind = sum(1 for t in tps if t.get("mrd_call") == "indeterminate")
cpms = [float(t.get("copies_per_ml", 0) or 0) for t in tps]
totals = [float(t.get("total_mapped_reads", 0) or 0) for t in tps]
norms = [t.get("normalizer") for t in tps]
traj = rep.get("trajectory", {})

warnings = []
if any(nm == "undetermined" for nm in norms):
    warnings.append("one or more timepoints lacked a usable normalizer (no spike-in and no total mapped reads)")
if rep.get("lod_source") == "declared_param":
    warnings.append("LoD is the declared assay param, not empirically determined (need >= 2 low-positive replicates)")
if str(rep.get("lob_source", "")).startswith("declared"):
    warnings.append("LoB set to 0 (insufficient blank replicates for an EP17 estimate)")
if totals and min(totals) < 1e6 and not any(nm == "spike_in" for nm in norms):
    warnings.append("low total mapped reads on the genome-equivalent normalizer path; copies/mL estimate is low-confidence")

summary = {
    "assay": rep.get("assay"),
    "target": rep.get("target"),
    "n_timepoints": len(tps),
    "overall_mrd_call": traj.get("overall_mrd_call"),
    "molecular_response": traj.get("molecular_response"),
    "trajectory_direction": traj.get("direction"),
    "baseline_copies_per_ml": traj.get("baseline_copies_per_ml"),
    "latest_copies_per_ml": traj.get("latest_copies_per_ml"),
    "lob_copies_per_ml": rep.get("lob_copies_per_ml"),
    "lod_copies_per_ml": rep.get("lod_copies_per_ml"),
    "normalizer_models": sorted(set(nm for nm in norms if nm)),
    "status": "ok",
    "note": "EBV/ctDNA cfDNA MRD quantification. copies/mL from target-region read counts via a spike-in or genome-equivalent normalizer (stated per timepoint); LoB/LoD by CLSI EP17-A2 when blank/low-positive replicates are supplied, else declared. Not a validated clinical result.",
}
with open("summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)

qc = {
    "n_timepoints": len(tps),
    "n_positive": n_pos,
    "n_negative": n_neg,
    "n_indeterminate": n_ind,
    "min_total_mapped_reads": min(totals) if totals else 0,
    "max_copies_per_ml": max(cpms) if cpms else 0,
    "lob_copies_per_ml": rep.get("lob_copies_per_ml"),
    "lod_copies_per_ml": rep.get("lod_copies_per_ml"),
    "lob_source": rep.get("lob_source"),
    "lod_source": rep.get("lod_source"),
    "n_blanks": rep.get("n_blanks"),
    "n_low_positives": rep.get("n_low_positives"),
    "spike_in_used": any(nm == "spike_in" for nm in norms),
    "warnings": warnings,
    "status": "ok",
}
with open("qc_metrics.json", "w") as fh:
    json.dump(qc, fh, indent=2)

print(json.dumps({"n_timepoints": len(tps), "overall_mrd_call": summary["overall_mrd_call"],
                  "n_positive": n_pos, "n_indeterminate": n_ind}, indent=2))
PYEOF
    """
}

workflow EBV_CFDNA_MRD {
    take:
    ch_input   // channel: tuple(bam, target_bed, target_counts_json)

    main:
    PREP_COUNTS(ch_input)
    QUANTIFY_MRD(PREP_COUNTS.out.counts)
    SUMMARISE(QUANTIFY_MRD.out.report, QUANTIFY_MRD.out.copies)

    emit:
    counts   = PREP_COUNTS.out.counts
    report   = QUANTIFY_MRD.out.report
    copies   = QUANTIFY_MRD.out.copies
    summary  = SUMMARISE.out.summary
    qc       = SUMMARISE.out.qc
    versions = PREP_COUNTS.out.versions
}

// Entry workflow for standalone execution.
workflow {
    ch_input = Channel.of(
        tuple(params.bam as String, params.target_bed as String, params.target_counts as String)
    )

    EBV_CFDNA_MRD(ch_input)

    EBV_CFDNA_MRD.out.summary.view { f -> "ebv cfdna mrd done: ${f}" }
}
