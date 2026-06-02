#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ribor
// The ribor package provides an R Interface for .ribo files. It provides functionality to read the .ri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ribor/inst/doc/ribor.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("ribor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ribor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ribor:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ribor:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ribor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ribor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ribor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ribor)
    library(jsonlite)

    # --- Read Length Distribution Analysis [] ---
    # Key functions: plot_length_distribution, get_length_distribution
    file_path <- system.file(
        "extdata", "HEK293_ingolia.ribo", 
        package = "ribor"
    )
    original_ribo <- Ribo(file_path, rename = rename_default)
    plot_length_distribution(
        x = original_ribo,
        region = "CDS",
        range.lower = 28,
        range.upper = 32,
        fraction = TRUE
    )
    rc <- get_length_distribution(
        ribo.object = original_ribo,
        region = "CDS",
        range.lower = 28,
        range.upper = 32
    )


    # --- Metagene Analysis [] ---
    # Key functions: plot_metagene, get_metagene, get_tidy_metagene
    file_path <- system.file(
        "extdata", "HEK293_ingolia.ribo", 
        package = "ribor"
    )
    original_ribo <- Ribo(file_path, rename = rename_default)
    plot_metagene(
        original_ribo,
        site = "start",
        experiment = c("GSM1606107"),
        range.lower = 28,
        range.upper = 32
    )
    tidy_meta_start <- get_tidy_metagene(
        ribo.object = original_ribo,
        site = "start",
        range.lower = 28,
        range.upper = 32,
        length = TRUE
    )
    plot_metagene(tidy_meta_start, normalize = TRUE)


    # --- Region Counts Analysis [] ---
    # Key functions: plot_region_counts, get_region_counts
    file_path <- system.file(
        "extdata", "HEK293_ingolia.ribo", 
        package = "ribor"
    )
    original_ribo <- Ribo(file_path, rename = rename_default)
    plot_region_counts(
        x = original_ribo,
        range.lower = 28,
        range.upper = 32
    )
    rc_info <- get_region_counts(
        ribo.object = original_ribo,
        region = c("UTR5", "CDS", "UTR3"),
        range.lower = 28,
        range.upper = 32
    )
    plot_region_counts(rc_info)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ribor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ribor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ribor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIBOR:", paste0("    ribor: ", packageVersion("ribor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribor_results.csv
    touch ${prefix}_ribor_output.rds
    echo "BIOC_RIBOR:" > versions.yml
    echo "    ribor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIBOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIBOR(ch_input)

    emit:
    results  = BIOC_RIBOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIBOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIBOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIBOR.out.versions  // channel: path(versions.yml)
}
