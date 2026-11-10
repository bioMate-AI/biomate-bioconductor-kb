#!/usr/bin/env nextflow
/*
 * bioimaging/radiology_radiomics_extraction
 *
 * RESEARCH-USE-ONLY radiomics feature extraction for CT / MR / PET images from SUPPLIED segmentations.
 * It computes standard first-order, shape and texture features (PyRadiomics, whose definitions follow the
 * Image Biomarker Standardisation Initiative) for the region of interest given as a mask. It does NOT segment,
 * diagnose or recommend treatment; radiologist review is required before any clinical use.
 *
 * Inputs : an image (NIfTI / NRRD / MHA file, or a DICOM series as a directory or .zip) and a mask on the same
 *          grid (NIfTI / NRRD / MHA). Either --input_image/--input_mask (one case) or --samplesheet
 *          (CSV: patient_id,image,mask[,modality,label,series_uid]; use absolute paths or object-store URIs).
 * Output : per case features_long.csv, features_wide.csv (one row), qc_summary.json, provenance.json,
 *          RESEARCH_USE_ONLY_report.txt, versions.yml; plus a cohort table features_wide_all.csv that joins to
 *          clinical and molecular data by patient_id.
 *
 * HONEST FAILURE CONTRACT: an empty mask, an image/mask grid mismatch, several DICOM series without a selection,
 * non-uniform DICOM slice spacing, a missing dependency or an unknown modality stops the run with a non-zero exit
 * and an actionable message. No value is estimated or fabricated. PET values are used as given (no DICOM SUV
 * conversion). Every setting and an SHA-256 of every input is recorded in provenance.json.
 *
 * Container: built from backend/scripts/domain_images/radiology/Dockerfile (Python 3.9; PyRadiomics 3.1.0 ships
 * wheels only up to Python 3.9). The process-level `container` directive below OVERRIDES the DB docker_image.
 */

nextflow.enable.dsl = 2

params.outdir          = './results'
params.input_image     = null          // one case: image file or DICOM series (directory / .zip)
params.input_mask      = null          // one case: segmentation on the image grid
params.samplesheet     = null          // many cases: CSV patient_id,image,mask[,modality,label,series_uid]
params.patient_id      = 'case01'
params.modality        = null          // REQUIRED: CT | MR | PET | OTHER (no silent default)
params.label           = 1
params.series_uid      = ''
params.bin_width       = ''            // overrides the modality default
params.bin_count       = ''
params.resample_spacing = ''           // "x,y,z" mm; none by default
params.normalize       = ''            // 0 | 1
params.correct_mask    = false
params.feature_classes = 'firstorder,shape,glcm,glrlm,glszm,gldm,ngtdm'
params.image_types     = 'Original'   // Original,LoG,Wavelet
params.log_sigma       = '1,2,3'
params.settings_json   = ''            // advanced PyRadiomics settings (JSON); recorded

process RADIOLOGY_RADIOMICS_EXTRACTION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-radiology:1.0'

    input:
    tuple val(meta), path(image), path(mask)

    output:
    tuple val(meta), path("features_long.csv"),               emit: long_table
    tuple val(meta), path("features_wide.csv"),               emit: wide
    tuple val(meta), path("qc_summary.json"),                 emit: qc
    tuple val(meta), path("provenance.json"),                 emit: provenance
    tuple val(meta), path("RESEARCH_USE_ONLY_report.txt"),    emit: report
    path "versions.yml",                                      emit: versions

    script:
    def series  = meta.series_uid ? "--series-uid '${meta.series_uid}'" : ''
    def binw    = params.bin_width.toString()  ? "--bin-width ${params.bin_width}"   : ''
    def binc    = params.bin_count.toString()  ? "--bin-count ${params.bin_count}"   : ''
    def resamp  = params.resample_spacing.toString() ? "--resample-spacing '${params.resample_spacing}'" : ''
    def norm    = params.normalize.toString()  ? "--normalize ${params.normalize}"   : ''
    def corr    = params.correct_mask ? '--correct-mask' : ''
    def sjson   = params.settings_json.toString() ? "--settings-json '${params.settings_json}'" : ''
    """
    python3 /opt/biomate/radiomics_extract.py \\
        --image '${image}' --mask '${mask}' --patient-id '${meta.id}' --modality ${meta.modality} --label ${meta.label} \\
        --feature-classes '${params.feature_classes}' --image-types '${params.image_types}' --log-sigma '${params.log_sigma}' \\
        ${series} ${binw} ${binc} ${resamp} ${norm} ${corr} ${sjson} --outdir .
    """
}

process RADIOLOGY_RADIOMICS_MERGE {
    label 'process_low'
    publishDir "${params.outdir}/merged", mode: 'copy'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-radiology:1.0'

    input:
    path(wide,  stageAs: 'wide_?.csv')
    path(qc,    stageAs: 'qc_?.json')
    path(prov,  stageAs: 'prov_?.json')

    output:
    path "features_wide_all.csv", emit: table
    path "qc_all.json",           emit: qc
    path "provenance_all.json",   emit: provenance

    script:
    """
    python3 /opt/biomate/merge_features.py --wide ${wide} --qc ${qc} --prov ${prov} --outdir .
    """
}

workflow RADIOLOGY_RADIOMICS_EXTRACTION_WORKFLOW {
    take:
    cases   // tuple(meta, image, mask)

    main:
    RADIOLOGY_RADIOMICS_EXTRACTION(cases)
    RADIOLOGY_RADIOMICS_MERGE(
        RADIOLOGY_RADIOMICS_EXTRACTION.out.wide.map { it[1] }.collect(),
        RADIOLOGY_RADIOMICS_EXTRACTION.out.qc.map { it[1] }.collect(),
        RADIOLOGY_RADIOMICS_EXTRACTION.out.provenance.map { it[1] }.collect()
    )

    emit:
    features   = RADIOLOGY_RADIOMICS_EXTRACTION.out.wide
    qc         = RADIOLOGY_RADIOMICS_EXTRACTION.out.qc
    provenance = RADIOLOGY_RADIOMICS_EXTRACTION.out.provenance
    report     = RADIOLOGY_RADIOMICS_EXTRACTION.out.report
    cohort     = RADIOLOGY_RADIOMICS_MERGE.out.table
    versions   = RADIOLOGY_RADIOMICS_EXTRACTION.out.versions
}

// Entry workflow for standalone execution
workflow {
    if (params.samplesheet) {
        cases = Channel.fromPath(params.samplesheet, checkIfExists: true).splitCsv(header: true).map { row ->
            def mod = (row.modality ?: params.modality)?.toString()?.toUpperCase()
            if (!mod) error "patient ${row.patient_id}: modality missing (CT, MR, PET or OTHER)"
            tuple([id: row.patient_id, modality: mod, label: (row.label ?: params.label), series_uid: (row.series_uid ?: params.series_uid)],
                  file(row.image, checkIfExists: true), file(row.mask, checkIfExists: true))
        }
    } else {
        if (!params.input_image || !params.input_mask) error "give --input_image and --input_mask, or --samplesheet"
        if (!params.modality) error "--modality is required (CT, MR, PET or OTHER); a silent default could mis-scale intensities"
        cases = Channel.of(tuple([id: params.patient_id, modality: params.modality.toString().toUpperCase(), label: params.label, series_uid: params.series_uid],
                                 file(params.input_image, checkIfExists: true), file(params.input_mask, checkIfExists: true)))
    }
    RADIOLOGY_RADIOMICS_EXTRACTION_WORKFLOW(cases)
}
