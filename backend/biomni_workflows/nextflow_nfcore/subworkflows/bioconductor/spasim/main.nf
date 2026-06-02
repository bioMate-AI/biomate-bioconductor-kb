#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spaSim
// A suite of functions for simulating spatial patterns of cells in tissue images. Output images are mu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spaSim/inst/doc/vignette.R
// Upstream  : RefManageR, knitr, rmarkdown, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("spaSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPASIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spasim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spasim:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spasim:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spasim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spasim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spasim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spaSim)
    library(PrintBibliography)
    library(jsonlite)

    # --- Cell Type Mixing [] ---
    # Key functions: simulate_mixing
    mix_bg <- simulate_mixing(
        bg_sample = bg,
        idents = c("Tumour", "Immune", "Others"),
        props = c(0.2, 0.3, 0.5), 
        plot_image = FALSE
    )


    # --- Tumour Cluster Simulation [] ---
    # Key functions: simulate_clusters
    cluster_properties <- list(
        C1 = list(
            name_of_cluster_cell = "Tumour", size = 500, shape = "Oval", 
            centre_loc = data.frame(x = 600, y = 600),
            infiltration_types = c("Immune1", "Others"), 
            infiltration_proportions = c(0.1, 0.05)
        ), 
        C2 = list(
            name_of_cluster_cell = "Immune1", size = 600, shape = "Irregular", 
            centre_loc = data.frame(x = 1500, y = 500),
            infiltration_types = c("Immune", "Others"),
            infiltration_proportions = c(0.1, 0.05)
        )
    )
    clusters <- simulate_clusters(
        bg_sample = mix_bg,
        n_clusters = 2,
        bg_type = "Others",
        cluster_properties = cluster_properties,
        plot_image = FALSE
    )


    # --- Immune Ring Simulation [] ---
    # Key functions: simulate_immune_rings
    immune_ring_properties <- list(
        I1 = list(
            name_of_cluster_cell = "Tumour", size = 500, 
            shape = "Circle", centre_loc = data.frame(x = 930, y = 1000), 
            infiltration_types = c("Immune1", "Immune2", "Others"), 
            infiltration_proportions = c(0.15, 0.05, 0.05),
            name_of_ring_cell = "Immune1", immune_ring_width = 150,
            immune_ring_infiltration_types = c("Immune2", "Others"), 
            immune_ring_infiltration_proportions = c(0.1, 0.15)
        )
    )
    rings <- simulate_immune_rings(
        bg_sample = bg,
        bg_type = "Others",
        n_ir = 1,
        ir_properties = immune_ring_properties,
        plot_image = FALSE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spasim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spasim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spasim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPASIM:", paste0("    spasim: ", packageVersion("spaSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spasim_results.csv
    touch ${prefix}_spasim_output.rds
    echo "BIOC_SPASIM:" > versions.yml
    echo "    spasim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPASIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPASIM(ch_input)

    emit:
    results  = BIOC_SPASIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPASIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPASIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPASIM.out.versions  // channel: path(versions.yml)
}
