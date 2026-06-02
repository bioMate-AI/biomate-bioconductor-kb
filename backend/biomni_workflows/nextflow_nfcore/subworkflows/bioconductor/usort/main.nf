#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: uSORT
// This package is designed to uncover the intrinsic cell progression path from single-cell RNA-seq dat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/uSORT/inst/doc/uSORT_quick_start.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("uSORT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_USORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-usort"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-usort:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-usort:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_usort_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_usort_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_usort_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(uSORT)
    library(jsonlite)


    # --- Eval=true [] ---
    # Key functions: args
    args(uSORT)

    # --- Eval=true [] ---
    # Key functions: list.files, uSORT, getwd, uSORT_example, autoSPIN, sWanderlust
    dir <- system.file('extdata', package='uSORT')
    file <- list.files(dir, pattern='.txt$', full=TRUE)
    # uSORT_results <- uSORT(exprs_file = file, 
    #                        log_transform = TRUE,
    #                        remove_outliers = TRUE,
    #                        project_name = "uSORT_example",
    #                        preliminary_sorting_method = "autoSPIN", 
    #                        refine_sorting_method = "sWanderlust",
    #                        result_directory = getwd(),
    #                        save_results = TRUE,
    #                        reproduce_seed = 1234)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_usort_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_usort_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_usort_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_USORT:", paste0("    usort: ", packageVersion("uSORT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_usort_results.csv
    touch ${prefix}_usort_output.rds
    echo "BIOC_USORT:" > versions.yml
    echo "    usort: 0.0.0" >> versions.yml
    """
}


workflow BIOC_USORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_USORT(ch_input)

    emit:
    results  = BIOC_USORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_USORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_USORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_USORT.out.versions  // channel: path(versions.yml)
}
