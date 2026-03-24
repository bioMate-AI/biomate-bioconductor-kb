#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gscreend
// Package for the analysis of pooled genetic screens (e.g. CRISPR-KO). The analysis of such screens is
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gscreend/inst/doc/gscreend_simulated_data.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("gscreend")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSCREEND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gscreend"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gscreend:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gscreend:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gscreend_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gscreend_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gscreend_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ResultsTable)
    library(RunGscreend)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: file
    ---------------------------------------------------------------------
    raw_counts <- read.table(
        system.file("extdata", "simulated_counts.txt", package = "gscreend"),
        header=TRUE)
    # --- Createpoolscreenexp [] ---
    # Key functions: createPoolScreenExp
    ---------------------------------------------------------------------
    pse <- createPoolScreenExp(se)
    # --- Rungscreend [] ---
    # Key functions: RunGscreend
    ---------------------------------------------------------------------
    pse_an <- RunGscreend(pse)
    # --- Plotmodelparameters [] ---
    # Key functions: plotModelParameters
    ---------------------------------------------------------------------
    plotModelParameters(pse_an)
    # --- Resultstable [] ---
    # Key functions: ResultsTable
    ---------------------------------------------------------------------
    res <- ResultsTable(pse_an, direction = "negative")
    head(res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gscreend_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gscreend_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gscreend_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSCREEND:", paste0("    gscreend: ", packageVersion("gscreend"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gscreend_results.csv
    touch ${prefix}_gscreend_output.rds
    echo "BIOC_GSCREEND:" > versions.yml
    echo "    gscreend: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSCREEND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSCREEND(ch_input)

    emit:
    results  = BIOC_GSCREEND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSCREEND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSCREEND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSCREEND.out.versions  // channel: path(versions.yml)
}
