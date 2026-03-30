#!/usr/bin/env nextflow
// ============================================================
// bioconductor_scrna_seq — End-to-end scRNA-seq analysis
//
// Pipeline:
//   1. BIOC_TXIMETA     — import alevin-fry / Cell Ranger counts
//   2. BIOC_SCRAN       — normalization, HVG selection, dimensionality reduction
//   3. BIOC_SINGLER     — automated cell type annotation
//   4. BIOC_MILR        — differential abundance between conditions
//   5. BIOC_CLUSTERPROFILER — marker gene enrichment
//
// Input: Cell Ranger / alevin-fry output directory
// Usage:
//   nextflow run bioconductor_scrna_seq/main.nf \
//     --input_dir  /path/to/cellranger_output \
//     --species    human \
//     --outdir     results/
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_TXIMETA         } from '../../subworkflows/bioconductor/tximeta/main.nf'
include { BIOC_SCRAN           } from '../../subworkflows/bioconductor/scran/main.nf'
include { BIOC_SINGLER         } from '../../subworkflows/bioconductor/singler/main.nf'
include { BIOC_MILR            } from '../../subworkflows/bioconductor/milr/main.nf'
include { BIOC_CLUSTERPROFILER } from '../../subworkflows/bioconductor/clusterprofiler/main.nf'

params.input_dir    = null
params.species      = 'human'         // human or mouse
params.min_cells    = 3
params.min_features = 200
params.n_hvgs       = 2000
params.outdir       = 'results'

workflow BIOCONDUCTOR_SCRNA_SEQ {

    take:
    ch_input  // [ val(meta), path(input_dir) ]

    main:
    ch_versions = Channel.empty()

    // Step 1: Import counts
    BIOC_TXIMETA(ch_input)
    ch_versions = ch_versions.mix(BIOC_TXIMETA.out.versions)

    // Step 2: Normalization + dimensionality reduction
    BIOC_SCRAN(BIOC_TXIMETA.out.rds)
    ch_versions = ch_versions.mix(BIOC_SCRAN.out.versions)

    // Step 3: Cell type annotation
    BIOC_SINGLER(BIOC_SCRAN.out.rds)
    ch_versions = ch_versions.mix(BIOC_SINGLER.out.versions)

    // Step 4: Differential abundance (miloR)
    BIOC_MILR(BIOC_SCRAN.out.rds)
    ch_versions = ch_versions.mix(BIOC_MILR.out.versions)

    // Step 5: Marker gene enrichment
    BIOC_CLUSTERPROFILER(BIOC_SINGLER.out.results)
    ch_versions = ch_versions.mix(BIOC_CLUSTERPROFILER.out.versions)

    emit:
    sce_rds       = BIOC_SCRAN.out.rds
    cell_types    = BIOC_SINGLER.out.results
    da_results    = BIOC_MILR.out.results
    enrichment    = BIOC_CLUSTERPROFILER.out.results
    versions      = ch_versions
}

workflow {
    if (!params.input_dir) {
        error "Usage: nextflow run main.nf --input_dir <path>"
    }
    ch_meta  = Channel.of([[id: 'scrna_seq']])
    ch_input = ch_meta.map { meta -> [meta, file(params.input_dir)] }
    BIOCONDUCTOR_SCRNA_SEQ(ch_input)
}
