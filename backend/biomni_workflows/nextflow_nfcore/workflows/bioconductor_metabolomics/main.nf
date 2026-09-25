#!/usr/bin/env nextflow
// ============================================================
// bioconductor_metabolomics — Untargeted LC-MS metabolomics
//
// Pipeline:
//   1. BIOC_XCMS           — peak detection, alignment, grouping
//   2. BIOC_CAMERA         — adduct/isotope annotation
//   3. BIOC_METABOANNOTATION — metabolite ID (HMDB/KEGG matching)
//   4. BIOC_CLUSTERPROFILER  — metabolic pathway enrichment
//
// Input: mzML or mzXML raw mass spec files
// Usage:
//   nextflow run bioconductor_metabolomics/main.nf \
//     --mzml_dir   /path/to/mzml_files \
//     --sample_sheet samples.csv \
//     --polarity   positive \
//     --outdir     results/
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING_WORKFLOW      as BIOC_XCMS            } from '../../subworkflows/bioconductor/xcms/main.nf'
include { BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION_WORKFLOW        as BIOC_CAMERA          } from '../../subworkflows/bioconductor/camera/main.nf'
include { BIOC_METABOANNOTATION_MATCH_VALUES_WORKFLOW               as BIOC_METABOANNOTATION } from '../../subworkflows/bioconductor/metaboannotation/main.nf'
include { BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS_WORKFLOW as BIOC_CLUSTERPROFILER } from '../../subworkflows/bioconductor/clusterprofiler/main.nf'

params.mzml_dir     = null
params.sample_sheet = null
params.polarity     = 'positive'
params.ppm          = 10
params.min_samples  = 3
params.outdir       = 'results'

workflow BIOCONDUCTOR_METABOLOMICS {

    take:
    ch_mzml     // [ val(meta), path(mzml_dir) ]
    ch_samples  // [ val(meta), path(samples.csv) ]

    main:
    ch_versions = Channel.empty()

    // Step 1: Peak detection + alignment
    BIOC_XCMS(ch_mzml)
    ch_versions = ch_versions.mix(BIOC_XCMS.out.versions)

    // Step 2: Adduct/isotope annotation
    BIOC_CAMERA(BIOC_XCMS.out.objects)
    ch_versions = ch_versions.mix(BIOC_CAMERA.out.versions)

    // Step 3: Metabolite identification
    BIOC_METABOANNOTATION(BIOC_CAMERA.out.objects)
    ch_versions = ch_versions.mix(BIOC_METABOANNOTATION.out.versions)

    // Step 4: Metabolic pathway enrichment
    // NB: the clusterprofiler subworkflow reads its gene list from params.gene_list
    // (no `take:` channel), so it is invoked without an upstream argument.
    BIOC_CLUSTERPROFILER()
    ch_versions = ch_versions.mix(BIOC_CLUSTERPROFILER.out.versions)

    emit:
    peak_matrix  = BIOC_XCMS.out.tables
    annotations  = BIOC_METABOANNOTATION.out.tables
    enrichment   = BIOC_CLUSTERPROFILER.out.tables
    versions     = ch_versions
}

workflow {
    if (!params.mzml_dir) {
        error "Usage: nextflow run main.nf --mzml_dir <path>"
    }
    ch_meta    = Channel.of([[id: 'metabolomics']])
    ch_mzml    = ch_meta.map { meta -> [meta, file(params.mzml_dir)] }
    ch_samples = params.sample_sheet ?
        ch_meta.map { meta -> [meta, file(params.sample_sheet)] } :
        ch_meta.map { meta -> [meta, []] }
    BIOCONDUCTOR_METABOLOMICS(ch_mzml, ch_samples)
}
