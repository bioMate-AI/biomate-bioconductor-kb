#!/usr/bin/env nextflow
// ============================================================
// bioconductor_methylation — WGBS / RRBS methylation analysis
//
// Pipeline:
//   1. BIOC_METHYLKIT    — differential methylation (CpG / tiles)
//   2. BIOC_MISSMETHYL   — gene-level methylation enrichment
//   3. BIOC_LIMMA        — linear model for differential methylation
//   4. BIOC_CLUSTERPROFILER — pathway enrichment on DMR genes
//
// Input: bismark coverage files (CX_report or bismark.cov)
// Usage:
//   nextflow run bioconductor_methylation/main.nf \
//     --coverage_dir /path/to/bismark_coverage \
//     --sample_sheet samples.csv \
//     --genome       hg38 \
//     --outdir       results/
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_METHYLKIT       } from '../../subworkflows/bioconductor/methylkit/main.nf'
include { BIOC_MISSMETHYL      } from '../../subworkflows/bioconductor/missmethyl/main.nf'
include { BIOC_LIMMA           } from '../../subworkflows/bioconductor/limma/main.nf'
include { BIOC_CLUSTERPROFILER } from '../../subworkflows/bioconductor/clusterprofiler/main.nf'

params.coverage_dir  = null
params.sample_sheet  = null
params.genome        = 'hg38'
params.diff_meth_pct = 25
params.qvalue        = 0.01
params.outdir        = 'results'

workflow BIOCONDUCTOR_METHYLATION {

    take:
    ch_coverage  // [ val(meta), path(coverage_dir) ]
    ch_samples   // [ val(meta), path(samples.csv) ]

    main:
    ch_versions = Channel.empty()

    // Step 1: Differential methylation
    BIOC_METHYLKIT(ch_coverage)
    ch_versions = ch_versions.mix(BIOC_METHYLKIT.out.versions)

    // Step 2: Gene-level methylation enrichment
    BIOC_MISSMETHYL(BIOC_METHYLKIT.out.results)
    ch_versions = ch_versions.mix(BIOC_MISSMETHYL.out.versions)

    // Step 3: Linear model (limma for array data)
    BIOC_LIMMA(BIOC_METHYLKIT.out.rds)
    ch_versions = ch_versions.mix(BIOC_LIMMA.out.versions)

    // Step 4: Pathway enrichment
    BIOC_CLUSTERPROFILER(BIOC_MISSMETHYL.out.results)
    ch_versions = ch_versions.mix(BIOC_CLUSTERPROFILER.out.versions)

    emit:
    dmr_results   = BIOC_METHYLKIT.out.results
    gene_meth     = BIOC_MISSMETHYL.out.results
    limma_results = BIOC_LIMMA.out.results
    enrichment    = BIOC_CLUSTERPROFILER.out.results
    versions      = ch_versions
}

workflow {
    if (!params.coverage_dir) {
        error "Usage: nextflow run main.nf --coverage_dir <path> --sample_sheet <csv>"
    }
    ch_meta     = Channel.of([[id: 'methylation']])
    ch_coverage = ch_meta.map { meta -> [meta, file(params.coverage_dir)] }
    ch_samples  = params.sample_sheet ?
        ch_meta.map { meta -> [meta, file(params.sample_sheet)] } :
        ch_meta.map { meta -> [meta, []] }
    BIOCONDUCTOR_METHYLATION(ch_coverage, ch_samples)
}
