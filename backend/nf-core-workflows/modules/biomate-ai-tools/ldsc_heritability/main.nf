#!/usr/bin/env nextflow
/*
 * population_genetics/ldsc_heritability  (3-phase + optional 4th-phase pipeline)
 *
 *   Phase A — Munge sumstats : munge_sumstats.py -> standardized .sumstats.gz
 *   Phase B — Heritability   : ldsc.py --h2 on EUR HapMap3 LD scores
 *   Phase C — Report         : parse _h2.log -> ldsc_report.{json,md}
 *   Phase D — (optional) rg  : ldsc.py --rg <a>,<b>  (when --cross_trait_sumstats set)
 *
 * Real-use-case anchor:
 *   Bulik-Sullivan, Loh, Finucane, et al. (2015a). "LD Score regression
 *   distinguishes confounding from polygenicity in genome-wide association
 *   studies." Nat Genet 47, 291-295.  doi: 10.1038/ng.3211
 *   Bulik-Sullivan, Finucane, Anttila, et al. (2015b). "An atlas of genetic
 *   correlations across human diseases and traits." Nat Genet 47, 1236-1241.
 *   doi: 10.1038/ng.3406
 *
 * Required upstream of:
 *   - Zhi UDIP-FA pipeline (PMC12458571) — TorchGWAS -> MAGMA -> METAL -> FUMA -> LDSC
 *
 * Upstream: https://github.com/bulik/ldsc  (BSD-3-Clause; Python 2.7 only)
 * Image:    biomate/ldsc:v1 — built from sibling container/Dockerfile.
 *           Bakes the LDSC repo + EUR HapMap3 LD scores + HapMap3 snplist + tutorial sumstats.
 *
 * Quick smoke (uses baked example, zero external inputs):
 *   nextflow run main.nf --use_baked_example true --outdir results
 *
 * Real run:
 *   nextflow run main.nf \
 *       --sumstats_input s3://bucket/my-gwas.txt \
 *       --outfile my_run \
 *       --outdir s3://bucket/runs/ldsc-001
 *
 * Cross-trait genetic correlation:
 *   nextflow run main.nf \
 *       --sumstats_input s3://bucket/scz.sumstats.gz \
 *       --cross_trait_sumstats s3://bucket/bip.sumstats.gz \
 *       --outdir s3://bucket/runs/ldsc-rg-001
 */
nextflow.enable.dsl = 2

params.outdir                = './results'
params.use_baked_example     = false
params.sumstats_input        = 'null'                                          // raw GWAS summary stats (SNP A1 A2 P N ... )
params.cross_trait_sumstats  = 'null'                                          // optional 2nd trait (already-munged .sumstats.gz)
params.ref_ld_chr            = '/opt/ldsc/eur_w_ld_chr/'                       // baked EUR HapMap3 LD scores
params.w_ld_chr              = '/opt/ldsc/eur_w_ld_chr/'                       // weight LD scores (same as ref-ld for std workflow)
params.merge_alleles         = '/opt/ldsc/eur_w_ld_chr/w_hm3.snplist'
params.outfile               = 'ldsc_run'

CONTAINER_LDSC = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ldsc:v1' \
    : 'biomate/ldsc:v1'

// [Phase A] Munge sumstats (standardize column names + restrict to HapMap3 SNPs)
process LDSC_MUNGE {
    tag "ldsc:phaseA"
    label 'process_low'
    container CONTAINER_LDSC
    publishDir "${params.outdir}/phaseA_munge", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("${params.outfile}.sumstats.gz"), path("munge.json"), emit: out

    script:
    def baked = (params.use_baked_example as Boolean) ? 'True' : 'False'
    """
    set -euo pipefail
    python - <<PY
    import json, os, sys, subprocess, shutil

    baked = ${baked}
    if baked:
        # Baked tutorial: PGC SCZ summary stats already in LDSC format.
        src = "/opt/ldsc/example/scz.sumstats.gz"
        if os.path.exists(src):
            shutil.copy(src, "${params.outfile}.sumstats.gz")
            info = {"phase":"A","baked_example":True,"src":src,"munge_skipped":True}
            json.dump(info, open("munge.json","w"), indent=2)
            sys.exit(0)
        # Fallback: write an empty stub (stub-run path)
        open("${params.outfile}.sumstats.gz","wb").close()
        json.dump({"phase":"A","baked_example":True,"stub":True}, open("munge.json","w"), indent=2)
        sys.exit(0)

    sumstats = "${params.sumstats_input}"
    if sumstats in ("null",""):
        print("ERROR: sumstats_input required when use_baked_example=false", file=sys.stderr)
        sys.exit(1)

    cmd = [
        "python", "/opt/ldsc/munge_sumstats.py",
        "--sumstats", sumstats,
        "--merge-alleles", "${params.merge_alleles}",
        "--out", "${params.outfile}",
    ]
    log = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
    open("munge.log","wb").write(log)
    info = {
        "phase":"A",
        "baked_example": False,
        "sumstats_input": sumstats,
        "output": "${params.outfile}.sumstats.gz",
        "log_tail": log.decode("utf-8","replace")[-1500:],
    }
    json.dump(info, open("munge.json","w"), indent=2)
    PY
    """

    stub:
    """
    touch ${params.outfile}.sumstats.gz
    echo '{"phase":"A","stub":true}' > munge.json
    """
}

// [Phase B] Heritability — ldsc.py --h2 against EUR HapMap3 LD scores
process LDSC_H2 {
    tag "ldsc:phaseB"
    label 'process_medium'
    container CONTAINER_LDSC
    publishDir "${params.outdir}/phaseB_h2", mode: 'copy'

    input:  tuple val(meta), path(sumstats_gz), path(munge_json)
    output: tuple val(meta), path("${params.outfile}_h2.log"), path("h2.json"), emit: out

    script:
    """
    set -euo pipefail
    python /opt/ldsc/ldsc.py \\
        --h2 ${sumstats_gz} \\
        --ref-ld-chr ${params.ref_ld_chr} \\
        --w-ld-chr ${params.w_ld_chr} \\
        --out ${params.outfile}_h2 2>&1 | tee h2_stdout.log

    python - <<PY
    import json, os
    p = "${params.outfile}_h2.log"
    txt = open(p).read() if os.path.exists(p) else ""
    info = {"phase":"B","h2_log":p,"log_tail": txt[-2000:]}
    json.dump(info, open("h2.json","w"), indent=2)
    PY
    """

    stub:
    """
    echo "Total Observed scale h2: 0.123 (0.045)" > ${params.outfile}_h2.log
    echo "Lambda GC: 1.05" >> ${params.outfile}_h2.log
    echo "Mean Chi^2: 1.12" >> ${params.outfile}_h2.log
    echo "Intercept: 1.01 (0.008)" >> ${params.outfile}_h2.log
    echo "Ratio: 0.08 (0.06)" >> ${params.outfile}_h2.log
    echo '{"phase":"B","stub":true}' > h2.json
    """
}

// [Phase C] Report — parse the _h2.log for the canonical 5 lines.
process LDSC_REPORT {
    tag "ldsc:phaseC"
    label 'process_low'
    container CONTAINER_LDSC
    publishDir "${params.outdir}/phaseC_report", mode: 'copy'

    input:  tuple val(meta), path(h2_log), path(h2_json)
    output: tuple val(meta), path("ldsc_report.json"), path("ldsc_report.md"), emit: out

    script:
    """
    set -euo pipefail
    python - <<PY
    import json, os, re

    p = "${h2_log}"
    txt = open(p).read() if os.path.exists(p) else ""

    def grab(pat):
        m = re.search(pat, txt)
        return m.group(1).strip() if m else None

    h2_obs      = grab(r"Total Observed scale h2:\\s*([0-9.\\-eE]+\\s*\\([0-9.\\-eE]+\\))")
    lambda_gc   = grab(r"Lambda GC:\\s*([0-9.\\-eE]+)")
    mean_chi2   = grab(r"Mean Chi\\^?2:\\s*([0-9.\\-eE]+)")
    intercept   = grab(r"Intercept:\\s*([0-9.\\-eE]+\\s*\\([0-9.\\-eE]+\\))")
    ratio       = grab(r"Ratio:\\s*([0-9.\\-eE]+\\s*\\([0-9.\\-eE]+\\)|<\\s*0|NA)")

    summary = {
        "phase":"C",
        "tool":"LDSC",
        "version":"v1.0.1",
        "citation":"Bulik-Sullivan 2015a 10.1038/ng.3211; 2015b 10.1038/ng.3406",
        "license":"BSD-3-Clause",
        "h2_observed_scale": h2_obs,
        "lambda_gc": lambda_gc,
        "mean_chi2": mean_chi2,
        "intercept": intercept,
        "ratio_intercept": ratio,
    }
    json.dump(summary, open("ldsc_report.json","w"), indent=2)

    fh = open("ldsc_report.md","w")
    fh.write("# LDSC Heritability Report\\n\\n")
    fh.write("Tool: LDSC v1.0.1 (Bulik-Sullivan 2015a/b, Nat Genet).\\n\\n")
    fh.write("| Metric | Value |\\n|---|---|\\n")
    for k in ("h2_observed_scale","lambda_gc","mean_chi2","intercept","ratio_intercept"):
        fh.write("| %s | %s |\\n" % (k, summary[k]))
    fh.close()
    PY
    """

    stub:
    """
    echo '{"phase":"C","stub":true}' > ldsc_report.json
    echo "# LDSC Heritability Report (stub)" > ldsc_report.md
    """
}

// [Phase D] (optional) cross-trait genetic correlation — only runs when
// --cross_trait_sumstats is provided (a second already-munged .sumstats.gz).
process LDSC_RG {
    tag "ldsc:phaseD"
    label 'process_medium'
    container CONTAINER_LDSC
    publishDir "${params.outdir}/phaseD_rg", mode: 'copy'

    input:  tuple val(meta), path(sumstats_gz), path(munge_json)
    output: tuple val(meta), path("${params.outfile}_rg.log"), path("rg.json"), emit: out

    script:
    """
    set -euo pipefail
    python /opt/ldsc/ldsc.py \\
        --rg ${sumstats_gz},${params.cross_trait_sumstats} \\
        --ref-ld-chr ${params.ref_ld_chr} \\
        --w-ld-chr ${params.w_ld_chr} \\
        --out ${params.outfile}_rg 2>&1 | tee rg_stdout.log

    python - <<PY
    import json, os
    p = "${params.outfile}_rg.log"
    txt = open(p).read() if os.path.exists(p) else ""
    json.dump({"phase":"D","rg_log":p,"log_tail":txt[-2000:]}, open("rg.json","w"), indent=2)
    PY
    """

    stub:
    """
    echo "Summary of Genetic Correlation Results" > ${params.outfile}_rg.log
    echo "rg: 0.65 (0.05)  p: 1.2e-30" >> ${params.outfile}_rg.log
    echo '{"phase":"D","stub":true}' > rg.json
    """
}

workflow {
    meta_ch = Channel.of([id: 'ldsc_heritability'])
    a = LDSC_MUNGE(meta_ch)
    b = LDSC_H2(a.out)
    LDSC_REPORT(b.out)
    if ((params.cross_trait_sumstats as String) != 'null' && (params.cross_trait_sumstats as String) != '') {
        LDSC_RG(a.out)
    }
}
