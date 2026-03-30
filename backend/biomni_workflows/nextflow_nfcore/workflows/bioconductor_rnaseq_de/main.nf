#!/usr/bin/env nextflow
// ============================================================
// bioconductor_rnaseq_de — End-to-end bulk RNA-seq DE analysis
//
// Pipeline:
//   1. BIOC_TXIMPORT    — import Salmon/kallisto quantification
//   2. BIOC_DESEQ2      — differential expression analysis
//   3. BIOC_EDGER       — independent DE with edgeR (optional)
//   4. BIOC_LIMMA       — voom + limma DE (optional)
//   5. BIOC_CLUSTERPROFILER — GO/KEGG enrichment on DE genes
//   6. BIOC_PATHVIEW    — KEGG pathway visualization
//
// Input channels:
//   ch_quant_files : [ val(meta), path(quant_dir/) ]
//                   — Salmon/kallisto output directories
//   ch_coldata     : [ val(meta), path(coldata.csv) ]
//                   — sample metadata (rownames = sample IDs)
//   ch_tx2gene     : [ val(meta), path(tx2gene.csv) ]
//                   — transcript → gene mapping
//
// Usage:
//   nextflow run bioconductor_rnaseq_de/main.nf \
//     --quant_dir  /path/to/salmon_results \
//     --coldata    coldata.csv \
//     --tx2gene    tx2gene.csv \
//     --design     "~condition" \
//     --outdir     results/
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_TXIMPORT        } from '../../subworkflows/bioconductor/tximport/main.nf'
include { BIOC_DESEQ2          } from '../../subworkflows/bioconductor/deseq2/main.nf'
include { BIOC_EDGER           } from '../../subworkflows/bioconductor/edger/main.nf'
include { BIOC_LIMMA           } from '../../subworkflows/bioconductor/limma/main.nf'
include { BIOC_CLUSTERPROFILER } from '../../subworkflows/bioconductor/clusterprofiler/main.nf'
include { BIOC_PATHVIEW        } from '../../subworkflows/bioconductor/pathview/main.nf'

params.quant_dir    = null
params.coldata      = null
params.tx2gene      = null
params.design       = "~condition"
params.padj_cutoff  = 0.05
params.lfc_cutoff   = 1.0
params.run_edger    = false
params.run_limma    = false
params.outdir       = 'results'

workflow BIOCONDUCTOR_RNASEQ_DE {

    take:
    ch_quant_files  // [ val(meta), path(quant_dir) ]
    ch_coldata      // [ val(meta), path(coldata.csv) ]
    ch_tx2gene      // [ val(meta), path(tx2gene.csv) ]

    main:
    ch_versions = Channel.empty()

    // Step 1: Import Salmon/kallisto quantification via tximport
    ch_tximport_input = ch_quant_files
        .join(ch_coldata,  by: [0])
        .join(ch_tx2gene,  by: [0])
        .map { meta, quant, coldata, tx2gene ->
            [ meta, quant ]  // tximport reads tx2gene from params
        }

    BIOC_TXIMPORT(ch_tximport_input)
    ch_versions = ch_versions.mix(BIOC_TXIMPORT.out.versions)

    // Step 2: DESeq2 differential expression
    // input: tximport RDS + coldata
    ch_deseq2_input = BIOC_TXIMPORT.out.rds
        .join(ch_coldata, by: [0])
        .map { meta, txi_rds, coldata -> [ meta, txi_rds ] }

    BIOC_DESEQ2(ch_deseq2_input)
    ch_versions = ch_versions.mix(BIOC_DESEQ2.out.versions)

    // Step 3 (optional): edgeR independent DE
    if (params.run_edger) {
        BIOC_EDGER(ch_deseq2_input)
        ch_versions = ch_versions.mix(BIOC_EDGER.out.versions)
    }

    // Step 4 (optional): limma/voom DE
    if (params.run_limma) {
        BIOC_LIMMA(ch_deseq2_input)
        ch_versions = ch_versions.mix(BIOC_LIMMA.out.versions)
    }

    // Step 5: GO/KEGG enrichment on significant DE genes
    BIOC_CLUSTERPROFILER(BIOC_DESEQ2.out.results)
    ch_versions = ch_versions.mix(BIOC_CLUSTERPROFILER.out.versions)

    // Step 6: KEGG pathway diagrams
    BIOC_PATHVIEW(BIOC_CLUSTERPROFILER.out.results)
    ch_versions = ch_versions.mix(BIOC_PATHVIEW.out.versions)

    emit:
    tximport_rds    = BIOC_TXIMPORT.out.rds             // tximport object
    de_results      = BIOC_DESEQ2.out.results           // DE table CSV
    de_rds          = BIOC_DESEQ2.out.rds               // DESeq2 dds object
    enrichment      = BIOC_CLUSTERPROFILER.out.results  // enrichment CSV
    pathway_plots   = BIOC_PATHVIEW.out.plots           // KEGG pathway PDFs
    versions        = ch_versions
}

// ---------------------------------------------------------------------------
// Entry point (standalone run)
// ---------------------------------------------------------------------------
workflow {
    if (!params.quant_dir || !params.coldata) {
        error "Usage: nextflow run main.nf --quant_dir <dir> --coldata <csv> --tx2gene <csv>"
    }

    ch_meta      = Channel.of([[id: 'rnaseq_de']])
    ch_quant     = ch_meta.map { meta -> [meta, file(params.quant_dir)] }
    ch_coldata   = ch_meta.map { meta -> [meta, file(params.coldata)] }
    ch_tx2gene   = params.tx2gene ?
        ch_meta.map { meta -> [meta, file(params.tx2gene)] } :
        ch_meta.map { meta -> [meta, []] }

    BIOCONDUCTOR_RNASEQ_DE(ch_quant, ch_coldata, ch_tx2gene)
}
