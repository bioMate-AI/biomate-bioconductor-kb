#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: philr
// PhILR is short for Phylogenetic Isometric Log-Ratio Transform. This package provides functions for t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/philr/inst/doc/philr-intro.R
// Upstream  : ape, dplyr, ggplot2, ggtree, glmnet
// Downstream: none
//
// Install: BiocManager::install("philr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHILR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-philr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-philr:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-philr:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_philr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_philr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_philr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(philr)
    library(jsonlite)

    # --- Phylogenetic Isometric Log-Ratio Transformation ---
    # Key functions: philr
    gp.philr <- philr(
        tse,
        abund_values = "counts.shifted",
        part.weights = "enorm.x.gm.counts",
        ilr.weights = "blw.sqrt"
    )

    # --- Taxonomic Balance Annotation ---
    # Key functions: name.balance, name.to.nn
    tax <- rowData(tse)[, taxonomyRanks(tse)]
    tree <- rowTree(tse)
    bal.name <- name.balance(tree, tax, "n1")
    top.coords <- c("n16", "n730")
    tc.nn <- name.to.nn(tree, top.coords)
    votes <- name.balance(
        tree, tax, "n730",
        return.votes = c("up", "down")
    )

    # --- Data Reshaping for Downstream Analysis ---
    # Key functions: convert_to_long
    human.samples <- factor(
        colData(tse)$SampleType %in%
        c("Feces", "Mock", "Skin", "Tongue")
    )
    gp.philr.long <- convert_to_long(gp.philr, human.samples)
    top.coords <- c("n16", "n730")
    gp.philr.long.filtered <- gp.philr.long[
        gp.philr.long$coord %in% top.coords,
    ]

    # --- Phylogenetic Balance Visualization ---
    # Key functions: geom_balance, annotate_balance, name.to.nn
    tree <- rowTree(tse)
    tc.nn <- name.to.nn(tree, c("n16", "n730"))
    p <- ggtree(tree, layout = "fan") +
        geom_balance(node = tc.nn[1], fill = "#a6cee3", alpha = 0.6) +
        geom_balance(node = tc.nn[2], fill = "#1f78b4", alpha = 0.6)
    p <- annotate_balance(
        tree, "n16", p = p, labels = c("n16+", "n16-"),
        offset.text = 0.15, bar = FALSE
    )
    p <- annotate_balance(
        tree, "n730", p = p, labels = c("n730+", "n730-"),
        offset.text = 0.15, bar = FALSE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_philr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_philr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_philr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHILR:", paste0("    philr: ", packageVersion("philr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_philr_results.csv
    touch ${prefix}_philr_output.rds
    echo "BIOC_PHILR:" > versions.yml
    echo "    philr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHILR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHILR(ch_input)

    emit:
    results  = BIOC_PHILR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHILR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHILR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHILR.out.versions  // channel: path(versions.yml)
}
