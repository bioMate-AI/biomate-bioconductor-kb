#!/usr/bin/env nextflow
/*
 * population_genetics/gcta_mlma  (4-phase pipeline)
 *
 *   Phase A — Input prep   : resolve PLINK .bed/.bim/.fam triplet + pheno (+ covars)
 *   Phase B — GRM build    : gcta64 --bfile <prefix> --make-grm --out <prefix>
 *   Phase C — MLMA         : gcta64 --mlma --bfile <prefix> --grm <prefix> --pheno ...
 *   Phase D — Report       : parse .mlma for top hits (p<5e-8) -> gcta_report.{json,md}
 *
 * Real-use-case anchor:
 *   Yang, Lee, Goddard, Visscher (2011). "GCTA: A tool for genome-wide complex
 *   trait analysis." American Journal of Human Genetics 88(1):76-82.
 *   doi: 10.1016/j.ajhg.2010.11.011
 *
 * Zhi's primary GWAS engine in the UDIP-FA paper (PMC12458571). Standard upstream
 * of MAGMA + METAL + LDSC + FUMA in the Zhi flagship pipeline.
 *
 * Upstream: https://yanglab.westlake.edu.cn/software/gcta/  (GPL-3.0)
 * Image:    biomate/gcta:v1 — built from sibling container/Dockerfile.
 *           Bakes the gcta64 binary + tutorial PLINK example.
 *
 * Quick smoke (uses baked example, zero external inputs):
 *   nextflow run main.nf --use_baked_example true --outdir results
 *
 * Real run:
 *   nextflow run main.nf \
 *       --bfile_prefix s3://bucket/my_cohort \
 *       --pheno_file   s3://bucket/my_pheno.txt \
 *       --qcovar_file  s3://bucket/my_pcs.txt \
 *       --outdir       s3://bucket/runs/gcta-001
 */
nextflow.enable.dsl = 2

params.outdir            = './results'
params.use_baked_example = false
params.bfile_prefix      = 'null'                                              // PLINK prefix (without .bed/.bim/.fam)
params.pheno_file        = 'null'                                              // FID IID phen
params.qcovar_file       = 'null'                                              // optional quantitative covariates (e.g. PCs)
params.outfile           = 'gcta_run'
params.top_n             = 50

CONTAINER_GCTA = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/gcta:v1' \
    : 'biomate/gcta:v1'

// [Phase A] Input resolution + validation.
process GCTA_INPUTS {
    tag "gcta:phaseA"
    label 'process_low'
    container CONTAINER_GCTA
    publishDir "${params.outdir}/phaseA_inputs", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("inputs.json"), emit: out

    script:
    def baked = (params.use_baked_example as Boolean) ? 'True' : 'False'
    """
    set -euo pipefail
    python3 - <<PY
    import json, os, sys

    baked = ${baked}
    if baked:
        # GCTA tutorial example baked at /opt/gcta/example
        bfile      = "/opt/gcta/example/test"
        pheno      = "/opt/gcta/example/test.phen"
        qcovar     = ""
    else:
        bfile  = "${params.bfile_prefix}"
        pheno  = "${params.pheno_file}"
        qcovar = "${params.qcovar_file}"
        if bfile in ("null","") or pheno in ("null",""):
            print("ERROR: bfile_prefix and pheno_file required when use_baked_example=false", file=sys.stderr)
            sys.exit(1)
        if qcovar in ("null",""):
            qcovar = ""

    info = {
        "phase":"A",
        "baked_example": baked,
        "bfile_prefix": bfile,
        "pheno_file": pheno,
        "qcovar_file": qcovar,
        "outfile": "${params.outfile}",
    }
    json.dump(info, open("inputs.json","w"), indent=2)
    PY
    """

    stub:
    """
    echo '{"phase":"A","stub":true}' > inputs.json
    """
}

// [Phase B] GRM construction
process GCTA_MAKE_GRM {
    tag "gcta:phaseB"
    label 'process_medium'
    container CONTAINER_GCTA
    publishDir "${params.outdir}/phaseB_grm", mode: 'copy'

    input:  tuple val(meta), path(inputs_json)
    output: tuple val(meta),
            path("${params.outfile}.grm.bin"),
            path("${params.outfile}.grm.N.bin"),
            path("${params.outfile}.grm.id"),
            path("grm.json"), emit: out

    script:
    """
    set -euo pipefail
    BFILE=\$(python3 -c "import json;print(json.load(open('${inputs_json}'))['bfile_prefix'])")
    /opt/gcta/gcta64 --bfile \${BFILE} --make-grm --out ${params.outfile} 2>&1 | tee grm_stdout.log

    python3 - <<PY
    import json, os
    log = open("grm_stdout.log").read() if os.path.exists("grm_stdout.log") else ""
    json.dump({
        "phase":"B",
        "grm_prefix":"${params.outfile}",
        "log_tail": log[-1500:],
    }, open("grm.json","w"), indent=2)
    PY
    """

    stub:
    """
    touch ${params.outfile}.grm.bin ${params.outfile}.grm.N.bin ${params.outfile}.grm.id
    echo '{"phase":"B","stub":true}' > grm.json
    """
}

// [Phase C] Mixed Linear Model Association (MLMA)
process GCTA_MLMA {
    tag "gcta:phaseC"
    label 'process_high'
    container CONTAINER_GCTA
    publishDir "${params.outdir}/phaseC_mlma", mode: 'copy'

    input:  tuple val(meta), path(grm_bin), path(grm_N), path(grm_id), path(grm_json), path(inputs_json)
    output: tuple val(meta), path("${params.outfile}.mlma"), path("mlma.json"), emit: out

    script:
    """
    set -euo pipefail
    BFILE=\$(python3 -c "import json;print(json.load(open('${inputs_json}'))['bfile_prefix'])")
    PHENO=\$(python3 -c "import json;print(json.load(open('${inputs_json}'))['pheno_file'])")
    QCOVAR=\$(python3 -c "import json;print(json.load(open('${inputs_json}'))['qcovar_file'])")

    CMD="/opt/gcta/gcta64 --mlma --bfile \${BFILE} --grm ${params.outfile} --pheno \${PHENO} --out ${params.outfile}"
    if [ -n "\${QCOVAR}" ]; then
        CMD="\${CMD} --qcovar \${QCOVAR}"
    fi
    echo "[gcta:mlma] \${CMD}"
    \${CMD} 2>&1 | tee mlma_stdout.log

    python3 - <<PY
    import json, os
    p = "${params.outfile}.mlma"
    log = open("mlma_stdout.log").read() if os.path.exists("mlma_stdout.log") else ""
    n_rows = 0
    if os.path.exists(p):
        with open(p) as fh:
            for i, line in enumerate(fh):
                if i == 0: continue
                if line.strip(): n_rows += 1
    json.dump({
        "phase":"C",
        "mlma_path": p,
        "n_rows": n_rows,
        "log_tail": log[-1500:],
    }, open("mlma.json","w"), indent=2)
    PY
    """

    stub:
    """
    printf "Chr\\tSNP\\tbp\\tA1\\tA2\\tFreq\\tb\\tse\\tp\\n" > ${params.outfile}.mlma
    printf "1\\trs12345\\t12345\\tA\\tG\\t0.21\\t0.12\\t0.02\\t1.2e-09\\n" >> ${params.outfile}.mlma
    echo '{"phase":"C","stub":true}' > mlma.json
    """
}

// [Phase D] Report — top hits at GW-sig (p < 5e-8) + summary.
process GCTA_REPORT {
    tag "gcta:phaseD"
    label 'process_low'
    container CONTAINER_GCTA
    publishDir "${params.outdir}/phaseD_report", mode: 'copy'

    input:  tuple val(meta), path(mlma), path(mlma_json)
    output: tuple val(meta), path("gcta_report.json"), path("gcta_report.md"), emit: out

    script:
    """
    set -euo pipefail
    python3 - <<PY
    import json, os
    import pandas as pd

    THRESH = 5e-8
    TOPN   = int("${params.top_n}")
    p = "${mlma}"
    n_total = 0; n_sig = 0; rows = []
    if os.path.exists(p):
        df = pd.read_csv(p, sep="\\t")
        pcol = "p" if "p" in df.columns else ("P" if "P" in df.columns else None)
        if pcol:
            df[pcol] = pd.to_numeric(df[pcol], errors='coerce')
            df = df.sort_values(pcol, ascending=True)
            n_total = int(len(df))
            n_sig   = int((df[pcol] < THRESH).sum())
            rows = df.head(TOPN).to_dict(orient='records')

    summary = {
        "phase":"D",
        "tool":"GCTA",
        "version":"1.94.4",
        "citation":"Yang 2011 AJHG 10.1016/j.ajhg.2010.11.011",
        "license":"GPL-3.0",
        "threshold_p": THRESH,
        "threshold_source": "GWAS genome-wide significance (5e-8)",
        "markers_total": n_total,
        "markers_significant": n_sig,
        "top_n": TOPN,
        "top_markers": rows,
    }
    json.dump(summary, open("gcta_report.json","w"), indent=2, default=str)

    fh = open("gcta_report.md","w")
    fh.write("# GCTA MLMA Report\\n\\n")
    fh.write("Tool: GCTA v1.94.4 (Yang 2011 AJHG).\\n\\n")
    fh.write("- Markers tested: **%d**\\n" % n_total)
    fh.write("- GW-sig markers (p < %g): **%d**\\n\\n" % (THRESH, n_sig))
    fh.write("## Top %d markers by p-value\\n\\n" % min(TOPN, n_total))
    if rows:
        cols = list(rows[0].keys())
        fh.write("| " + " | ".join(cols) + " |\\n")
        fh.write("| " + " | ".join(["---"]*len(cols)) + " |\\n")
        for r in rows:
            fh.write("| " + " | ".join(str(r[c]) for c in cols) + " |\\n")
    else:
        fh.write("_No rows parsed._\\n")
    fh.close()
    PY
    """

    stub:
    """
    echo '{"phase":"D","stub":true}' > gcta_report.json
    echo "# GCTA MLMA Report (stub)" > gcta_report.md
    """
}

workflow {
    meta_ch = Channel.of([id: 'gcta_mlma'])
    a = GCTA_INPUTS(meta_ch)
    b = GCTA_MAKE_GRM(a.out)
    // join GRM outputs with inputs.json so Phase C can read bfile/pheno/qcovar
    c_in = b.out.join(a.out)
    c = GCTA_MLMA(c_in)
    GCTA_REPORT(c.out)
}
