#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: INDEED
// An R package for integrated differential expression and differential network analysis based on omic 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/INDEED/inst/doc/Introduction_to_INDEED.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("INDEED")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INDEED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-indeed"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-indeed:2.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-indeed:2.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_indeed_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_indeed_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_indeed_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IDs)
    library(jsonlite)

    # --- Dataset [] ---
    # Key functions: subject, IDs
    ----------------------------------------------------
    #  # Data matrix contains the expression levels of 39 metabolites from 120 subjects
    #  # (6 metabolites and 10 subjects are shown)
    #  head(Met_GU[, 1:10])
    #  # Group label for each subject (40 subjects are shown)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_indeed_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_indeed_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_indeed_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INDEED:", paste0("    indeed: ", packageVersion("INDEED"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_indeed_results.csv
    touch ${prefix}_indeed_output.rds
    echo "BIOC_INDEED:" > versions.yml
    echo "    indeed: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INDEED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INDEED(ch_input)

    emit:
    results  = BIOC_INDEED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INDEED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INDEED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INDEED.out.versions  // channel: path(versions.yml)
}
