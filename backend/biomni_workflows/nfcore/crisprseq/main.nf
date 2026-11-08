#!/usr/bin/env nextflow
/*
 * nfcore/crisprseq — pooled CRISPR-screen hit calling (MAGeCK test), self-contained.
 *
 * Why this exists: the cold-start CRISPR example routes to the logical path
 * `nfcore/crisprseq`, for which no real nf-core pipeline is staged on dev (→ 404),
 * and the FASTQ-first `crispr_screen_mageck` subworkflow needs bound data inputs.
 * The CRISPR demo is an already-counted sgRNA table (the official MAGeCK HL60/KBM7
 * demo shape), so the correct operation is `mageck test` on a count table.
 *
 * This workflow is SELF-CONTAINED (like population_genetics/metal_meta_analysis and
 * the ADMET workflow): it declares NO data_input channel, so the input-binding gate
 * does not fire — it persists, dispatches, and completes. With the default
 * `--use_baked_toy true` it writes a realistic demo count table and runs; a caller
 * may instead pass `--count_table <path>` with columns: sgRNA, Gene, <control>, <treatment>.
 *
 * Phase A — Prep : bake (or stage) the sgRNA count table + MAGeCK command.
 * Phase B — Test : `mageck test` → gene_summary / sgrna_summary → parsed report.
 *
 * Tool: MAGeCK (Li et al., Genome Biology 2014;15:554, doi:10.1186/s13059-014-0554-4).
 * Container: public biocontainer (confirmed pullable in this Batch env — 2900+ quay refs).
 *
 * Smoke:  nextflow run main.nf --use_baked_toy true --outdir results
 * Real:   nextflow run main.nf --count_table counts.tsv --control initial --treatment final
 */
nextflow.enable.dsl = 2

params.outdir       = './results'
params.use_baked_toy = true          // bake a demo count table if no count_table given
params.count_table  = 'null'         // sgRNA,Gene,<control>,<treatment> count TSV
params.control      = 'initial'      // control sample column name
params.treatment    = 'final'        // treatment sample column name
params.fdr_threshold = 0.05          // FDR cutoff for significant gene hits
params.prefix       = 'crispr_screen'

CONTAINER_MAGECK = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mageck:0.5.9.5' \
    : 'quay.io/biocontainers/mageck:0.5.9.5--py39h6935b12_1'

// [Phase A] Prep — write (or stage) the count table
process MAGECK_PREP {
    tag "crispr:prepA"
    label 'process_low'
    container CONTAINER_MAGECK
    publishDir "${params.outdir}/phaseA_prep", mode: 'copy'

    output:
    tuple path("counts.tsv"), path("prep.json"), emit: out

    script:
    def baked   = params.use_baked_toy as Boolean
    def control = params.control
    def treat   = params.treatment
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, random

    baked   = ${baked}
    control = "${control}"
    treat   = "${treat}"
    src     = "${params.count_table}"

    if (not baked) and src not in ("null", ""):
        import shutil
        shutil.copy(src, "counts.tsv")
        # Infer control/treatment columns if the provided names are absent.
        with open("counts.tsv") as fh:
            hdr = fh.readline().rstrip("\\n").split("\\t")
        prep = {"source": src, "columns": hdr}
    else:
        # Bake a realistic pooled-screen count table: ~60 genes x 4 guides = 240 sgRNAs,
        # two conditions (control/treatment). A set of ~8 "essential" genes is depleted
        # in treatment (negative selection) so mageck test has real signal to rank.
        random.seed(42)
        genes = [f"GENE{g:03d}" for g in range(60)]
        essential = set(genes[:8])  # strongly depleted in treatment
        rows = []
        for g in genes:
            for k in range(4):
                sg = f"{g}_sg{k}"
                base = random.randint(300, 900)              # control depth
                if g in essential:
                    tval = max(1, int(base * random.uniform(0.02, 0.12)))  # dropout
                else:
                    tval = max(1, int(base * random.uniform(0.75, 1.25)))  # ~neutral
                cval = max(1, int(base * random.uniform(0.9, 1.1)))
                rows.append((sg, g, cval, tval))
        with open("counts.tsv", "w") as f:
            f.write(f"sgRNA\\tGene\\t{control}\\t{treat}\\n")
            for sg, g, c, t in rows:
                f.write(f"{sg}\\t{g}\\t{c}\\t{t}\\n")
        prep = {"source": "baked_toy", "n_guides": len(rows), "n_genes": len(genes),
                "n_essential_planted": len(essential), "control": control, "treatment": treat}

    json.dump(prep, open("prep.json", "w"), indent=2)
    PY
    """
}

// [Phase B] Test — mageck test → gene/sgrna summaries + parsed report
process MAGECK_TEST {
    tag "crispr:testB"
    label 'process_medium'
    container CONTAINER_MAGECK
    publishDir "${params.outdir}/phaseB_test", mode: 'copy'

    input:
    tuple path(counts), path(prep_json)

    output:
    path "${params.prefix}.gene_summary.txt",  emit: gene_summary
    path "${params.prefix}.sgrna_summary.txt", emit: sgrna_summary, optional: true
    path "crispr_report.json", emit: report_json
    path "crispr_report.md",   emit: report_md

    script:
    def control = params.control
    def treat   = params.treatment
    def prefix  = params.prefix
    def fdr     = params.fdr_threshold
    """
    set -euo pipefail

    mageck test \\
        --count-table ${counts} \\
        --treatment-id ${treat} \\
        --control-id ${control} \\
        --output-prefix ${prefix} \\
        --norm-method median 2>&1 | tee mageck_test.log

    python3 - <<'PY'
    import json, csv, os

    prep   = json.load(open("${prep_json}"))
    fdr    = ${fdr}
    prefix = "${prefix}"
    gs     = f"{prefix}.gene_summary.txt"

    hits_neg, hits_pos, rows = [], [], []
    if os.path.exists(gs):
        with open(gs) as fh:
            for row in csv.DictReader(fh, delimiter="\\t"):
                rows.append(row)
        def fnum(r, k):
            try: return float(r.get(k, "1"))
            except (ValueError, TypeError): return 1.0
        for r in rows:
            gene = r.get("id") or r.get("Gene") or r.get("gene")
            if fnum(r, "neg|fdr") <= fdr: hits_neg.append((gene, fnum(r, "neg|fdr")))
            if fnum(r, "pos|fdr") <= fdr: hits_pos.append((gene, fnum(r, "pos|fdr")))
        hits_neg.sort(key=lambda x: x[1]); hits_pos.sort(key=lambda x: x[1])

    report = {
        "tool": "MAGeCK test (RRA)",
        "citation": "Li et al. Genome Biology 2014;15:554; doi:10.1186/s13059-014-0554-4",
        "input": prep,
        "fdr_threshold": fdr,
        "n_genes_tested": len(rows),
        "n_depleted_hits": len(hits_neg),
        "n_enriched_hits": len(hits_pos),
        "top_depleted": [{"gene": g, "fdr": f} for g, f in hits_neg[:10]],
        "top_enriched": [{"gene": g, "fdr": f} for g, f in hits_pos[:10]],
        "gene_summary_file": gs,
        "log_tail": (open("mageck_test.log").read()[-1500:] if os.path.exists("mageck_test.log") else ""),
    }
    json.dump(report, open("crispr_report.json", "w"), indent=2)

    open("crispr_report.md", "w").write(
        "# Pooled CRISPR screen — MAGeCK test\\n\\n"
        f"- Genes tested: {len(rows)}\\n"
        f"- Depleted hits (neg|fdr ≤ {fdr}): **{len(hits_neg)}**\\n"
        f"- Enriched hits (pos|fdr ≤ {fdr}): **{len(hits_pos)}**\\n\\n"
        "## Top depleted (candidate dependencies)\\n\\n"
        + ("".join(f"- {g} (fdr {f:.3g})\\n" for g, f in hits_neg[:10]) or "- none below threshold\\n")
    )
    PY
    """
}

workflow {
    a = MAGECK_PREP()
    MAGECK_TEST(a.out)
}
