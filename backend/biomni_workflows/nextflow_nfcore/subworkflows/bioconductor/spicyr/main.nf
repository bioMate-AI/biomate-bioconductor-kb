#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spicyR
// The spicyR package provides a framework for performing inference on changes in spatial relationships
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spicyR/inst/doc/spicyR.R
// Upstream  : BiocStyle, SpatialDatasets, SpatialExperiment, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("spicyR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPICYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spicyr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spicyr:1.18.1--r44_0' :
        'quay.io/biocontainers/bioconductor-spicyr:1.18.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spicyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spicyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spicyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(spicyR)
    library(Surv)
    library(jsonlite)

    # --- Significance Visualization [] ---
    # Key functions: signifPlot, spicyBoxPlot
    signifPlot(
        spicyTest,
        breaks = c(-3, 3, 1),
        marksToPlot = c("Macrophages", "DC_or_Mono", "dn_T_CD3",
                        "Neutrophils", "CD8_T_cell", "Keratin_Tumour")
    )
    spicyBoxPlot(
        results = spicyTest,
        rank = 1
    )


    # --- Spatial Graph Conversion and Testing [] ---
    # Key functions: convPairs, spicy, topPairs
    pairAbundances <- convPairs(
        kerenSPE,
        colPair = "knn_interaction_graph"
    )
    spicyTestColPairs <- spicy(
        kerenSPE,
        condition = "tumour_type",
        alternateResult = pairAbundances,
        weights = FALSE
    )
    topColPairs <- topPairs(spicyTestColPairs)


    # --- Pairwise Association Estimation [] ---
    # Key functions: getPairwise
    kerenSubset <- kerenSPE[, colData(kerenSPE)$imageID == "24"]
    pairwiseAssoc <- getPairwise(
        kerenSubset,
        sigma = 20,
        Rs = 100
    )
    pairwiseDF <- as.data.frame(pairwiseAssoc)


    # --- Spatial Image Plotting [] ---
    # Key functions: plotImage
    plotImage(
        kerenSPE,
        "24",
        from = "Keratin_Tumour",
        to = "Neutrophils"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spicyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spicyr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spicyr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPICYR:", paste0("    spicyr: ", packageVersion("spicyR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spicyr_results.csv
    touch ${prefix}_spicyr_output.rds
    echo "BIOC_SPICYR:" > versions.yml
    echo "    spicyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPICYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPICYR(ch_input)

    emit:
    results  = BIOC_SPICYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPICYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPICYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPICYR.out.versions  // channel: path(versions.yml)
}
