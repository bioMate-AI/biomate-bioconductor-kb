#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Xeva
// The Xeva package provides efficient and powerful functions for patient-drived xenograft (PDX) based 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Xeva/inst/doc/Xeva.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("Xeva")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XEVA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xeva"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xeva:1.22.1--r44_0' :
        'quay.io/biocontainers/bioconductor-xeva:1.22.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xeva_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xeva_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xeva_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Xeva)
    library(jsonlite)

    # --- BatchInfo analysis [] ---
    # Key functions: install_github, batchInfo, plotPDX, waterfall, summarizeMolecularProfiles, response, drugSensitivitySig
    mut <- summarizeMolecularProfiles(brca,drug = "BYL719", mDataType="mutation")
    model.type <- Biobase::exprs(mut)["CDK13", ]
    model.type[grepl("Mut", model.type)] <- "mutation"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xeva_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xeva_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xeva_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XEVA:", paste0("    xeva: ", packageVersion("Xeva"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xeva_results.csv
    touch ${prefix}_xeva_output.rds
    echo "BIOC_XEVA:" > versions.yml
    echo "    xeva: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XEVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XEVA(ch_input)

    emit:
    results  = BIOC_XEVA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XEVA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XEVA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XEVA.out.versions  // channel: path(versions.yml)
}
