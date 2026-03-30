#!/usr/bin/env nextflow
// ============================================================
// bioconductor_multiomics — Multi-omics factor analysis
//
// Pipeline:
//   1. BIOC_MULTIASSAYEXPERIMENT — harmonise multi-modal datasets
//   2. BIOC_MOFA2               — multi-omics factor analysis
//   3. BIOC_DESEQ2              — per-factor DE on RNA component
//   4. BIOC_CLUSTERPROFILER     — enrichment of factor-associated genes
//
// Input: RNA-seq count matrix + proteomics/metabolomics matrix + sample metadata
// Usage:
//   nextflow run bioconductor_multiomics/main.nf \
//     --rna_matrix      rna_counts.csv \
//     --protein_matrix  protein_abundance.csv \
//     --coldata         coldata.csv \
//     --n_factors       10 \
//     --outdir          results/
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_MULTIASSAYEXPERIMENT } from '../../subworkflows/bioconductor/multiassayexperiment/main.nf'
include { BIOC_MOFA2                } from '../../subworkflows/bioconductor/mofa2/main.nf'
include { BIOC_DESEQ2               } from '../../subworkflows/bioconductor/deseq2/main.nf'
include { BIOC_CLUSTERPROFILER      } from '../../subworkflows/bioconductor/clusterprofiler/main.nf'

params.rna_matrix     = null
params.protein_matrix = null
params.coldata        = null
params.n_factors      = 10
params.outdir         = 'results'

workflow BIOCONDUCTOR_MULTIOMICS {

    take:
    ch_rna      // [ val(meta), path(rna_counts.csv) ]
    ch_protein  // [ val(meta), path(protein_abundance.csv) ]
    ch_coldata  // [ val(meta), path(coldata.csv) ]

    main:
    ch_versions = Channel.empty()

    // Step 1: Combine modalities into MultiAssayExperiment
    ch_mae_input = ch_rna.join(ch_protein, by: [0])
        .join(ch_coldata, by: [0])
        .map { meta, rna, prot, col -> [meta, rna] }
    BIOC_MULTIASSAYEXPERIMENT(ch_mae_input)
    ch_versions = ch_versions.mix(BIOC_MULTIASSAYEXPERIMENT.out.versions)

    // Step 2: MOFA2 factor analysis
    BIOC_MOFA2(BIOC_MULTIASSAYEXPERIMENT.out.rds)
    ch_versions = ch_versions.mix(BIOC_MOFA2.out.versions)

    // Step 3: DE analysis on top factor-weighted genes
    BIOC_DESEQ2(ch_rna)
    ch_versions = ch_versions.mix(BIOC_DESEQ2.out.versions)

    // Step 4: Pathway enrichment
    BIOC_CLUSTERPROFILER(BIOC_DESEQ2.out.results)
    ch_versions = ch_versions.mix(BIOC_CLUSTERPROFILER.out.versions)

    emit:
    mae_rds      = BIOC_MULTIASSAYEXPERIMENT.out.rds
    mofa_model   = BIOC_MOFA2.out.rds
    factors      = BIOC_MOFA2.out.results
    enrichment   = BIOC_CLUSTERPROFILER.out.results
    versions     = ch_versions
}

workflow {
    if (!params.rna_matrix || !params.coldata) {
        error "Usage: nextflow run main.nf --rna_matrix <csv> --protein_matrix <csv> --coldata <csv>"
    }
    ch_meta    = Channel.of([[id: 'multiomics']])
    ch_rna     = ch_meta.map { meta -> [meta, file(params.rna_matrix)] }
    ch_protein = params.protein_matrix ?
        ch_meta.map { meta -> [meta, file(params.protein_matrix)] } :
        ch_meta.map { meta -> [meta, []] }
    ch_coldata = ch_meta.map { meta -> [meta, file(params.coldata)] }
    BIOCONDUCTOR_MULTIOMICS(ch_rna, ch_protein, ch_coldata)
}
