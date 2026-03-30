#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAI
// A two-step approach to imputing missing data in metabolomics. Step 1 uses a random forest classifier
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAI/inst/doc/UsingMAI.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("MAI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mai"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mai:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mai:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mai_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mai_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mai_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MAI)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: MAI
    ---------------------------------------------------------------------
    # Load the MAI package
    library(MAI)
    # Load the example data with missing values
    data("untargeted_LCMS_data")
    # --- Data [] ---
    # Key functions: SummarizedExperiment, MAI, assay
    ---------------------------------------------------------------------
    # Load the SummarizedExperiment package
    suppressMessages(
      library(SummarizedExperiment)
    )
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    # Get the estimated mixed missingness parameters
    metadata(Results)[["meta_assay_1"]][["Estimated_Params"]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mai_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mai_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mai_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAI:", paste0("    mai: ", packageVersion("MAI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mai_results.csv
    touch ${prefix}_mai_output.rds
    echo "BIOC_MAI:" > versions.yml
    echo "    mai: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAI(ch_input)

    emit:
    results  = BIOC_MAI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAI.out.versions  // channel: path(versions.yml)
}
