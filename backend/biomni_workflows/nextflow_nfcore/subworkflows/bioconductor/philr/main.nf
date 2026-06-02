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

    # --- Rowdata [] ---
    # Key functions: rowData, taxonomyRanks, balance
    ---------------------------------------------------------------------
    # Extract taxonomy table from the TreeSE object
    tax <- rowData(tse)[,taxonomyRanks(tse)]
    # Get name balances
    name.balance(tree, tax, 'n1')
    # --- Factor [] ---
    # Key functions: factor, colData
    ---------------------------------------------------------------------
    human.samples <- factor(colData(tse)$SampleType %in% c("Feces", "Mock", "Skin", "Tongue"))
    # --- Dist [] ---
    # Key functions: dist, frame, cmdscale
    ---------------------------------------------------------------------
    # Distances between samples based on philr transformed data
    gp.dist <- dist(gp.philr, method="euclidean")
    # Calculate MDS for the distance matrix
    d <- as.data.frame(cmdscale(gp.dist))
    # --- Factor [] ---
    # Key functions: factor, ggplot, aes, geom_point, labs
    ---------------------------------------------------------------------
    # Add some metadata for the visualization
    d$SampleType <- factor(metadata$SampleType)
    # Create a plot
    # --- Matrix [] ---
    # Key functions: coefficients
    ---------------------------------------------------------------------
    top.coords <- as.matrix(coefficients(glmmod, s=0.2526))
    top.coords <- rownames(top.coords)[which(top.coords != 0)]
    (top.coords <- top.coords[2:length(top.coords)]) # remove the intercept as a coordinate
    # --- Sapply [] ---
    # Key functions: balance
    ---------------------------------------------------------------------
    tc.names <- sapply(top.coords, function(x) name.balance(tree, tax, x))
    tc.names
    # --- Balance [] ---
    # Key functions: balance
    ---------------------------------------------------------------------
    votes <- name.balance(tree, tax, 'n730', return.votes = c('up', 'down'))
    votes[[c('up.votes', 'Family')]]   # Numerator at Family Level
    votes[[c('down.votes', 'Family')]] # Denominator at Family Level
    # --- Convert To Long [] ---
    # Key functions: convert_to_long, filter, ggplot, aes, geom_boxplot, facet_grid, labs, theme_bw
    ---------------------------------------------------------------------
    gp.philr.long <- convert_to_long(gp.philr, human.samples) %>%
      filter(coord %in% top.coords)
    ggplot(gp.philr.long, aes(x=labels, y=value)) +
      geom_boxplot(fill='lightgrey') +

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
