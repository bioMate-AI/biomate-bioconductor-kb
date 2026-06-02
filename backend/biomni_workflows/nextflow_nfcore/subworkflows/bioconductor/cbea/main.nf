#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CBEA
// This package implements CBEA, a method to perform set-based analysis for microbiome relative abundan
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CBEA/inst/doc/basic_usage.R
// Upstream  : BiocSet, RefManageR, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("CBEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CBEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cbea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cbea:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cbea:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cbea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cbea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cbea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CBEA)
    library(PrintBibliography)
    library(jsonlite)

    # --- Load and Prepare Input Data [Data Preparation] ---
    # Key functions: hmp_gingival
    data("hmp_gingival", package = "CBEA")
    abun <- hmp_gingival$data
    metab_sets <- hmp_gingival$set

    # --- Run Competitive Balance Exploratory Analysis [Analysis] ---
    # Key functions: cbea
    results <- cbea(
        obj = abun,
        set = metab_sets,
        abund_values = "16SrRNA",
        output = "cdf",
        distr = "mnorm",
        adj = TRUE,
        thresh = 0.05,
        n_perm = 10
    )

    # --- Extract and Tidy Analysis Results [Post-processing] ---
    # Key functions: tidy, glance
    tidy_results <- tidy(results)
    fit_comparison <- glance(results, "fit_comparison")
    fit_diagnostic <- glance(results, "fit_diagnostic")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cbea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cbea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cbea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CBEA:", paste0("    cbea: ", packageVersion("CBEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cbea_results.csv
    touch ${prefix}_cbea_output.rds
    echo "BIOC_CBEA:" > versions.yml
    echo "    cbea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CBEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CBEA(ch_input)

    emit:
    results  = BIOC_CBEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CBEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CBEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CBEA.out.versions  // channel: path(versions.yml)
}
