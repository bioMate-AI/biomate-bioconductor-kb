#!/usr/bin/env nextflow
/*
 * genomics/acmg_variant_interpretation
 *
 * Clinical variant interpretation via EVIDENCE AGGREGATION + mechanically-
 * computable ACMG/AMP-2015 criteria. This subworkflow does NOT emit a
 * black-box "Pathogenic" verdict. It:
 *
 *   1. ANNOTATE : run Ensembl VEP with gnomAD allele frequency, ClinVar
 *                 clinical significance, consequence, and (optionally) CADD /
 *                 REVEL / AlphaMissense / gene-constraint plugins -> a real
 *                 annotated TSV of per-variant evidence.
 *   2. ACMG     : apply ONLY the defensibly-computable criteria
 *                 (BA1, BS1, PM2_Supporting, PP3/BP4, and a PVS1 precondition
 *                 FLAG) via acmg_criteria.py; every applied criterion cites its
 *                 evidence value + source.
 *   3. DOSSIER  : emit a structured JSON dossier + human-readable Markdown
 *                 report per variant. Criteria requiring human/functional/
 *                 segregation judgement (PS3, PP1, PM3, PS1, PM1, ...) are
 *                 listed as "requires expert review", never auto-applied.
 *
 * HONESTY BOUNDARY (enforced in code, not just docs):
 *   - The provisional tier is a TRANSPARENT SUM of auto-applied criteria only,
 *     explicitly labelled "NOT a final clinical classification".
 *   - Missing evidence -> criterion unknown -> provisional call defaults to VUS.
 *   - HONEST-FAIL: if no variant carries usable evidence, build_dossier.py
 *     exits non-zero and NO dossier is fabricated.
 *   - NO random-number generation anywhere; identical evidence -> identical call.
 *
 * Inputs:
 *   params.input     : a VCF/VCF.GZ to annotate, OR an already-annotated
 *                      VEP TSV / CSV / JSON variant list (see params.pre_annotated).
 *   params.pre_annotated : if true, skip VEP and feed params.input straight
 *                      into the ACMG step (for lists already carrying gnomAD AF
 *                      + predictor + consequence columns).
 *
 * Outputs:
 *   <id>.vep.tsv                 : annotated evidence table (when VEP is run)
 *   <id>_acmg_dossier.json       : structured, auditable per-variant dossier
 *   <id>_acmg_dossier_report.md  : human-readable report
 *
 * References:
 *   Richards et al. Genet Med 2015 (ACMG/AMP-2015; PMID 25741868)
 *   Tavtigian et al. Genet Med 2020 (points framework; PMID 32720330)
 *   Abou Tayoun et al. Hum Mutat 2018 (ClinGen PVS1; PMID 30192042)
 *   McLaren et al. Genome Biol 2016 (VEP)
 */

nextflow.enable.dsl = 2

params.input              = null
params.pre_annotated      = false          // input is already an annotated TSV/JSON
params.max_credible_af    = null           // gene/disease-specific max credible AF (BS1)

// VEP annotation params (mirrors genomics/vep_annotation)
params.species            = 'homo_sapiens'
params.assembly           = 'GRCh38'
params.vep_cache          = '/vep_cache'
params.vep_cache_version  = '110'
params.gnomad             = true
params.clinvar            = true
params.cadd               = false
params.cadd_snvs          = null
params.cadd_indels        = null

params.outdir             = './results/acmg_variant_interpretation'
params.publish_dir_mode   = 'copy'
params.max_memory         = '32.GB'
params.max_cpus           = 8
params.max_time           = '24.h'

/*
 * 1. VEP annotation -> tabular evidence TSV (CSQ fields incl. gnomAD AF,
 *    ClinVar, consequence, and any enabled predictor plugin).
 */
process VEP_ANNOTATE {
    tag "${meta.id}"
    label 'process_medium'
    container 'ensemblorg/ensembl-vep:release_110.0'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(vcf)

    output:
    tuple val(meta), path("${meta.id}.vep.tsv"), emit: tsv

    when:
    task.ext.when == null || task.ext.when

    script:
    def plugins = []
    if (params.cadd && params.cadd_snvs)
        plugins << "CADD,${params.cadd_snvs},${params.cadd_indels}"
    def plugin_args = plugins.collect { "--plugin ${it}" }.join(" ")
    def gnomad_arg  = params.gnomad  ? "--af_gnomad --max_af" : ""
    def clinvar_arg = params.clinvar ? "--check_existing"     : ""
    """
    vep \\
        --input_file ${vcf} --output_file ${meta.id}.vep.tsv \\
        --format vcf --tab \\
        --symbol --numbers --biotype --hgvs --hgvsg --canonical --mane_select \\
        --sift b --polyphen b \\
        --species ${params.species} --assembly ${params.assembly} \\
        --cache --offline --cache_version ${params.vep_cache_version} \\
        --dir_cache ${params.vep_cache} \\
        --fork ${task.cpus} --no_stats --force_overwrite \\
        ${gnomad_arg} ${clinvar_arg} ${plugin_args}

    # VEP --tab writes '##' meta lines and a '#Uploaded_variation' header.
    # Convert the header line to a plain TSV header for the ACMG parser.
    grep -v '^##' ${meta.id}.vep.tsv | sed '1s/^#//' > ${meta.id}.vep.clean.tsv
    mv ${meta.id}.vep.clean.tsv ${meta.id}.vep.tsv
    """
}

/*
 * 2 + 3. Apply computable ACMG criteria and emit dossier JSON + Markdown.
 *        Runs the pure-stdlib Python engine staged from the subworkflow dir.
 *        HONEST-FAILs (non-zero exit) if no variant has usable evidence.
 */
process ACMG_DOSSIER {
    tag "${meta.id}"
    label 'process_low'
    container 'python:3.11-slim'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(annotated)
    path(acmg_module)          // acmg_criteria.py
    path(builder)              // build_dossier.py

    output:
    tuple val(meta), path("${meta.id}_acmg_dossier.json"),      emit: json
    tuple val(meta), path("${meta.id}_acmg_dossier_report.md"), emit: report

    when:
    task.ext.when == null || task.ext.when

    script:
    def maxaf = params.max_credible_af != null ? "--max-credible-af ${params.max_credible_af}" : ""
    """
    python3 ${builder} \\
        --input ${annotated} \\
        --out-json ${meta.id}_acmg_dossier.json \\
        --out-md ${meta.id}_acmg_dossier_report.md \\
        ${maxaf}
    """
}

workflow ACMG_VARIANT_INTERPRETATION {
    take:
    ch_input   // channel: [ val(meta), path(vcf_or_annotated) ]

    main:
    // Resolve the Python engine relative to THIS subworkflow file so it works
    // whether main.nf is run directly or included from a parent pipeline.
    def module_dir  = "${moduleDir}"
    def acmg_module = file("${module_dir}/acmg_criteria.py")
    def builder     = file("${module_dir}/build_dossier.py")

    if (params.pre_annotated) {
        // Input is already an annotated TSV/CSV/JSON evidence table.
        ACMG_DOSSIER(ch_input, acmg_module, builder)
    } else {
        VEP_ANNOTATE(ch_input)
        ACMG_DOSSIER(VEP_ANNOTATE.out.tsv, acmg_module, builder)
    }

    emit:
    json   = ACMG_DOSSIER.out.json
    report = ACMG_DOSSIER.out.report
}

workflow {
    if (!params.input) {
        error "HONEST-FAIL: params.input is required (a VCF to annotate, or a " +
              "pre-annotated VEP TSV/JSON with params.pre_annotated=true). " +
              "Refusing to emit a dossier from nothing."
    }
    Channel.fromPath(params.input)
        .map { f -> [[id: f.baseName.replaceAll(/\.(vcf|tsv|csv|json).*/, '')], f] }
        .set { ch_input }
    ACMG_VARIANT_INTERPRETATION(ch_input)
}
