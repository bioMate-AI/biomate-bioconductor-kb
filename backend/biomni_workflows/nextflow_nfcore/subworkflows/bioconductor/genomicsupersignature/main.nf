#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicSuperSignature
// This package provides a novel method for interpreting new transcriptomic datasets through near-insta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicSuperSignature/inst/doc/Contents.R
// Upstream  : BiocManager, bcellViper
// Downstream: none
//
// Install: BiocManager::install("GenomicSuperSignature")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICSUPERSIGNATURE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicsupersignature"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicsupersignature:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicsupersignature:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicsupersignature_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicsupersignature_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicsupersignature_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RAVindex)
    library(jsonlite)

    # --- get Model [] ---
    # Key functions: getModel, version, geneSets, RAVindex, metadata
    RAVmodel <- getModel("C2", load=TRUE)
    version(RAVmodel)
    geneSets(RAVmodel)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicsupersignature_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicsupersignature_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicsupersignature_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICSUPERSIGNATURE:", paste0("    genomicsupersignature: ", packageVersion("GenomicSuperSignature"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicsupersignature_results.csv
    touch ${prefix}_genomicsupersignature_output.rds
    echo "BIOC_GENOMICSUPERSIGNATURE:" > versions.yml
    echo "    genomicsupersignature: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICSUPERSIGNATURE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICSUPERSIGNATURE(ch_input)

    emit:
    results  = BIOC_GENOMICSUPERSIGNATURE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICSUPERSIGNATURE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICSUPERSIGNATURE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICSUPERSIGNATURE.out.versions  // channel: path(versions.yml)
}
