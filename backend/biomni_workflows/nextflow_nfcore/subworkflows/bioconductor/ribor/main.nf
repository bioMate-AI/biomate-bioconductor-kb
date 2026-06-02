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

    # --- plot length distribution ribo [] ---
    # Key functions: plot_length_distribution

    # --- plot length distribution UTR5 ribo [] ---
    # Key functions: plot_length_distribution

    # --- get length dist basic [] ---
    # Key functions: get_length_distribution

    # --- plot length distribution from dataframe [] ---
    # Key functions: plot_length_distribution
    plot_length_distribution(rc, fraction = TRUE)
    # --- learn metagene radius [] ---
    # Key functions: get_info
    get_info(original.ribo)$attributes$metagene_radius
    # --- plot metagene ribo start [] ---
    # Key functions: plot_metagene

    # --- plot metagene ribo [] ---
    # Key functions: plot_metagene

    # --- plot metagene from dt [] ---
    # Key functions: plot_metagene
    plot_metagene(tidy.meta.start, normalize = TRUE)
    # --- plot region counts ribo [] ---
    # Key functions: plot_region_counts

    # --- get region counts default [] ---
    # Key functions: get_region_counts
    rc <- get_region_counts(original.ribo,
    region      = c("CDS"))
    # --- get region counts transcript [] ---
    # Key functions: get_region_counts
    rc <- get_region_counts(original.ribo,
    region      = c("CDS"))
    # --- get region counts full [] ---
    # Key functions: get_region_counts
    rc <- get_region_counts(original.ribo,
    region      = c("CDS"))
    # --- get region counts non [] ---
    # Key functions: get_region_counts

    # --- get region counts normalize [] ---
    # Key functions: get_region_counts
    rc <- get_region_counts(original.ribo,
    region      = c("CDS"))
    # --- plot region counts dt [] ---
    # Key functions: plot_region_counts


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
