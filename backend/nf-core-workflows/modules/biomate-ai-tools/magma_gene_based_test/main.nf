#!/usr/bin/env nextflow
/*
 * population_genetics/magma_gene_based_test  (4-phase pipeline)
 *
 *   Phase A — Inputs        : resolve sumstats + reference panel + gene-loc
 *   Phase B — SNP-to-gene   : magma --annotate (window 35,10 kb)
 *   Phase C — Gene-based    : magma gene-based test on annotated SNPs
 *   Phase D — Report        : parse .genes.out -> top hits + magma_report.{json,md}
 *
 * Real-use-case anchor:
 *   de Leeuw, Mooij, Heskes & Posthuma (2015). "MAGMA: Generalized Gene-Set
 *   Analysis of GWAS Data." PLOS Computational Biology 11(4):e1004219.
 *   doi: 10.1371/journal.pcbi.1004219
 *
 * Required upstream of:
 *   - Zhi UDIP-FA pipeline (PMC12458571) — TorchGWAS -> MAGMA -> METAL -> FUMA -> LDSC
 *   - Zhao scGWAS pipeline (PMC9575201)  — MAGMA -> scGWAS
 *
 * Upstream: https://cncr.nl/research/magma/  (AFL-3.0)
 * Image:    biomate/magma:v1 — built from sibling container/Dockerfile.
 *           Bakes the binary + 1000G EUR ref + NCBI37.3 gene-loc + tutorial sumstats.
 *
 * Quick smoke (uses baked example, zero external inputs):
 *   nextflow run main.nf --use_baked_example true --outdir results
 *
 * Real run:
 *   nextflow run main.nf \
 *       --sumstats_input s3://bucket/my-gwas.txt \
 *       --sample_size 200000 \
 *       --outfile my_run \
 *       --outdir s3://bucket/runs/magma-001
 */
nextflow.enable.dsl = 2

params.outdir            = './results'
params.use_baked_example = false
params.sumstats_input    = 'null'                                            // s3:// or local path; SNP, P columns + N (or pass --sample_size)
params.reference_panel   = '/opt/magma/reference/g1000_eur'                  // bfile prefix (.bim/.bed/.fam)
params.gene_loc_file     = '/opt/magma/reference/NCBI37.3.gene.loc'
params.sample_size       = 0                                                 // pass through to --pval N=
params.window            = '35,10'                                           // upstream,downstream kb
params.outfile           = 'magma_run'
params.top_n             = 50                                                // top-N gene rows for report

CONTAINER_MAGMA = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/magma:v1' \
    : 'biomate/magma:v1'

// [Phase A] Input resolution + validation
process MAGMA_INPUTS {
    tag "magma:phaseA"
    label 'process_low'
    container CONTAINER_MAGMA
    publishDir "${params.outdir}/phaseA_inputs", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("inputs.json"), emit: out

    script:
    def baked = (params.use_baked_example as Boolean) ? 'True' : 'False'
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, sys

    baked = ${baked}
    if baked:
        # Baked tutorial: MAGMA's gwas_sample.txt + g1000_eur + NCBI37.3.gene.loc
        sumstats = "/opt/magma/example/gwas_sample.txt"
        sample_size = ${params.sample_size} or 100000  # tutorial uses N=100k
    else:
        sumstats = "${params.sumstats_input}"
        if sumstats in ("null", ""):
            print("ERROR: sumstats_input required when use_baked_example=false", file=sys.stderr)
            sys.exit(1)
        sample_size = ${params.sample_size}
        if sample_size <= 0:
            # Allow N column in sumstats — MAGMA will pick it up with `ncol=N`.
            pass

    info = {
        "phase": "A",
        "baked_example": baked,
        "sumstats_path": sumstats,
        "reference_panel": "${params.reference_panel}",
        "gene_loc_file": "${params.gene_loc_file}",
        "sample_size": sample_size,
        "window_kb": "${params.window}",
        "outfile": "${params.outfile}",
    }
    json.dump(info, open("inputs.json","w"), indent=2)
    PY
    """
}

// [Phase B] SNP-to-gene annotation
process MAGMA_ANNOTATE {
    tag "magma:phaseB"
    label 'process_low'
    container CONTAINER_MAGMA
    publishDir "${params.outdir}/phaseB_annotate", mode: 'copy'

    input:  tuple val(meta), path(inputs_json)
    output: tuple val(meta), path("${params.outfile}.genes.annot"), path("annotate.json"), emit: out

    script:
    """
    set -euo pipefail
    BIM="${params.reference_panel}.bim"
    GLOC="${params.gene_loc_file}"

    /opt/magma/magma \\
        --annotate window=${params.window} \\
        --snp-loc \$BIM \\
        --gene-loc \$GLOC \\
        --out ${params.outfile} 2>&1 | tee annotate.log

    python3 - <<'PY'
    import json, os
    n = 0
    p = "${params.outfile}.genes.annot"
    if os.path.exists(p):
        with open(p) as fh:
            for line in fh:
                if not line.startswith("#") and line.strip():
                    n += 1
    json.dump({
        "phase": "B",
        "annot_file": p,
        "genes_annotated": n,
        "window_kb": "${params.window}",
        "log_tail": open("annotate.log").read()[-1500:] if os.path.exists("annotate.log") else "",
    }, open("annotate.json","w"), indent=2)
    PY
    """
}

// [Phase C] Gene-based test
process MAGMA_GENE_TEST {
    tag "magma:phaseC"
    label 'process_medium'
    container CONTAINER_MAGMA
    publishDir "${params.outdir}/phaseC_gene_test", mode: 'copy'

    input:  tuple val(meta), path(annot_file), path(annotate_json)
    output: tuple val(meta),
            path("${params.outfile}.genes.out"),
            path("${params.outfile}.genes.raw"),
            path("gene_test.json"), emit: out

    script:
    // Resolve sumstats path from Phase-A info (re-read so caller can change params).
    def baked = params.use_baked_example as Boolean
    def sumstats = baked ? "/opt/magma/example/gwas_sample.txt" : "${params.sumstats_input}"
    def n_arg = (params.sample_size as int) > 0 ? "N=${params.sample_size}" : "ncol=N"
    """
    set -euo pipefail
    BFILE="${params.reference_panel}"

    /opt/magma/magma \\
        --bfile \$BFILE \\
        --pval ${sumstats} ${n_arg} \\
        --gene-annot ${annot_file} \\
        --out ${params.outfile} 2>&1 | tee gene_test.log

    python3 - <<'PY'
    import json, os
    p = "${params.outfile}.genes.out"
    n = 0
    if os.path.exists(p):
        with open(p) as fh:
            for line in fh:
                if not line.startswith("#") and line.strip():
                    n += 1
        n = max(0, n - 1)  # subtract header
    json.dump({
        "phase": "C",
        "genes_out": p,
        "genes_raw": "${params.outfile}.genes.raw",
        "genes_tested": n,
        "log_tail": open("gene_test.log").read()[-1500:] if os.path.exists("gene_test.log") else "",
    }, open("gene_test.json","w"), indent=2)
    PY
    """
}

// [Phase D] Report — top hits at gene-wide-significance threshold (p < 2.7e-6)
process MAGMA_REPORT {
    tag "magma:phaseD"
    label 'process_low'
    container CONTAINER_MAGMA
    publishDir "${params.outdir}/phaseD_report", mode: 'copy'

    input:  tuple val(meta), path(genes_out), path(genes_raw), path(gene_test_json)
    output: tuple val(meta), path("magma_report.json"), path("magma_report.md"), emit: out

    script:
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os
    import pandas as pd

    THRESH = 2.7e-6  # genome-wide gene-significance (Bonferroni over ~18.4k genes)
    TOPN   = int("${params.top_n}")

    p = "${genes_out}"
    rows = []
    if os.path.exists(p):
        # MAGMA .genes.out is whitespace-separated with header. Columns include
        # GENE CHR START STOP NSNPS NPARAM N ZSTAT P.
        df = pd.read_csv(p, delim_whitespace=True, comment='#')
        df.columns = [c.upper() for c in df.columns]
        if 'P' in df.columns:
            df = df.sort_values('P', ascending=True)
            sig = df[df['P'] < THRESH]
            top = df.head(TOPN)
            rows = top.to_dict(orient='records')
            n_sig = int(len(sig))
            n_total = int(len(df))
        else:
            n_sig, n_total = 0, 0
    else:
        n_sig, n_total = 0, 0

    summary = {
        "phase": "D",
        "tool": "MAGMA",
        "version": "v1.10",
        "citation": "de Leeuw et al. 2015 PLOS Comp Bio 10.1371/journal.pcbi.1004219",
        "license": "AFL-3.0",
        "threshold_p": THRESH,
        "threshold_source": "genome-wide gene-significance (Bonferroni / ~18.4k genes)",
        "genes_total": n_total,
        "genes_significant": n_sig,
        "top_n": TOPN,
        "top_genes": rows,
    }
    json.dump(summary, open("magma_report.json","w"), indent=2, default=str)

    with open("magma_report.md","w") as fh:
        fh.write("# MAGMA Gene-Based Test Report\\n\\n")
        fh.write("Tool: MAGMA v1.10 (de Leeuw 2015, PLOS Comp Bio).\\n\\n")
        fh.write(f"- Genes tested: **{n_total}**\\n")
        fh.write(f"- Genes significant (p < {THRESH:g}): **{n_sig}**\\n\\n")
        fh.write(f"## Top {min(TOPN, n_total)} genes by p-value\\n\\n")
        if rows:
            cols = list(rows[0].keys())
            fh.write("| " + " | ".join(cols) + " |\\n")
            fh.write("| " + " | ".join(["---"]*len(cols)) + " |\\n")
            for r in rows:
                fh.write("| " + " | ".join(str(r[c]) for c in cols) + " |\\n")
        else:
            fh.write("_No genes-out rows parsed._\\n")
    PY
    """
}

workflow {
    meta_ch = Channel.of([id: 'magma_gene_based_test'])
    a = MAGMA_INPUTS(meta_ch)
    b = MAGMA_ANNOTATE(a.out)
    c = MAGMA_GENE_TEST(b.out)
    MAGMA_REPORT(c.out)
}
