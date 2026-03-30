#!/usr/bin/env nextflow
// ============================================================
// bioconductor_chipseq — ChIP-seq / CUT&RUN downstream analysis
//
// Pipeline (post-peak-calling):
//   1. BIOC_CHIPSEEKER   — peak annotation (nearest gene, genomic region)
//   2. BIOC_DIFFBIND     — differential binding analysis between conditions
//   3. BIOC_CHROMVAR     — TF motif accessibility scoring
//   4. BIOC_CLUSTERPROFILER — GO/KEGG enrichment on annotated genes
//
// Input: BAM files + peak BED files from nf-core/chipseq or nf-core/cutandrun
// Usage:
//   nextflow run bioconductor_chipseq/main.nf \
//     --peaks_dir  /path/to/macs2_peaks \
//     --bam_dir    /path/to/aligned_bams \
//     --genome     hg38 \
//     --outdir     results/
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_CHIPSEEKER      } from '../../subworkflows/bioconductor/chipseeker/main.nf'
include { BIOC_DIFFBIND        } from '../../subworkflows/bioconductor/diffbind/main.nf'
include { BIOC_CHROMVAR        } from '../../subworkflows/bioconductor/chromvar/main.nf'
include { BIOC_CLUSTERPROFILER } from '../../subworkflows/bioconductor/clusterprofiler/main.nf'

params.peaks_dir = null
params.bam_dir   = null
params.genome    = 'hg38'
params.outdir    = 'results'

workflow BIOCONDUCTOR_CHIPSEQ {

    take:
    ch_peaks    // [ val(meta), path(peaks.bed) ]
    ch_bams     // [ val(meta), path(sample.bam) ]

    main:
    ch_versions = Channel.empty()

    // Step 1: Annotate peaks to nearest genes
    BIOC_CHIPSEEKER(ch_peaks)
    ch_versions = ch_versions.mix(BIOC_CHIPSEEKER.out.versions)

    // Step 2: Differential binding
    ch_diffbind_input = ch_peaks.join(ch_bams, by: [0])
        .map { meta, peaks, bam -> [meta, peaks] }
    BIOC_DIFFBIND(ch_diffbind_input)
    ch_versions = ch_versions.mix(BIOC_DIFFBIND.out.versions)

    // Step 3: TF motif scoring
    BIOC_CHROMVAR(ch_peaks)
    ch_versions = ch_versions.mix(BIOC_CHROMVAR.out.versions)

    // Step 4: Enrichment of annotated genes
    BIOC_CLUSTERPROFILER(BIOC_CHIPSEEKER.out.results)
    ch_versions = ch_versions.mix(BIOC_CLUSTERPROFILER.out.versions)

    emit:
    peak_annotation = BIOC_CHIPSEEKER.out.results
    diff_binding    = BIOC_DIFFBIND.out.results
    motif_scores    = BIOC_CHROMVAR.out.results
    enrichment      = BIOC_CLUSTERPROFILER.out.results
    versions        = ch_versions
}

workflow {
    if (!params.peaks_dir) {
        error "Usage: nextflow run main.nf --peaks_dir <path> --bam_dir <path>"
    }
    ch_meta  = Channel.of([[id: 'chipseq']])
    ch_peaks = ch_meta.map { meta -> [meta, file(params.peaks_dir)] }
    ch_bams  = params.bam_dir ?
        ch_meta.map { meta -> [meta, file(params.bam_dir)] } :
        ch_meta.map { meta -> [meta, []] }
    BIOCONDUCTOR_CHIPSEQ(ch_peaks, ch_bams)
}
