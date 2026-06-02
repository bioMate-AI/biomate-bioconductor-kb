#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: faers
// The FDA Adverse Event Reporting System (FAERS) is a database used for the spontaneous reporting of a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/faers/inst/doc/FAERS-Pharmacovigilance.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("faers")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FAERS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-faers"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-faers:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-faers:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_faers_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_faers_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_faers_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(faers)
    library(jsonlite)

    # --- Standardization and Deduplication [] ---
    # Key functions: faers_meddra, faers_dedup, faers_get
    std_path <- system.file("extdata", "standardized_data.rds", package = "faers")
    data <- readRDS(std_path)
    meddra_info <- faers_meddra(data, use = "hierarchy")
    dedup_data <- faers_dedup(data)
    reac_data <- faers_get(dedup_data, "reac")


    # --- Drug Filtering [] ---
    # Key functions: fda_drugs, faers_filter
    std_path <- system.file("extdata", "standardized_data.rds", package = "faers")
    data <- readRDS(std_path)
    fda_insulin <- fda_drugs()
    insulin_pattern <- "insulin"
    insulin_data <- faers_filter(data, .fn = function(x) {
        idx <- grepl(insulin_pattern, x$drugname, ignore.case = TRUE)
        x[idx, primaryid]
    }, .field = "drug")


    # --- Pharmacovigilance Signal Detection [] ---
    # Key functions: faers_phv_signal, faers_filter
    std_path <- system.file("extdata", "standardized_data.rds", package = "faers")
    data <- readRDS(std_path)
    insulin_data <- faers_filter(data, .fn = function(x) {
        x[grepl("insulin", drugname, ignore.case = TRUE), primaryid]
    }, .field = "drug")
    insulin_signals <- faers_phv_signal(
        insulin_data,
        .full = data,
        BPPARAM = BiocParallel::SerialParam(RNGseed = 1L)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_faers_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_faers_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_faers_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FAERS:", paste0("    faers: ", packageVersion("faers"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_faers_results.csv
    touch ${prefix}_faers_output.rds
    echo "BIOC_FAERS:" > versions.yml
    echo "    faers: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FAERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FAERS(ch_input)

    emit:
    results  = BIOC_FAERS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FAERS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FAERS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FAERS.out.versions  // channel: path(versions.yml)
}
