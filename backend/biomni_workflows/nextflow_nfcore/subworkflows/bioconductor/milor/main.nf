#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miloR
// Milo performs single-cell differential abundance testing. Cell states are modelled as representative
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miloR/inst/doc/milo_contrasts.R
// Upstream  : ExperimentHub
// Downstream: none
//
// Install: BiocManager::install("miloR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MILOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-milor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-milor:2.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-milor:2.2.0--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_milor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_milor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_milor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(miloR)
    library(MouseSMARTseqData)
    library(jsonlite)

    # --- Graph Construction and Neighborhood Counting [] ---
    # Key functions: buildGraph, makeNhoods, countCells, plotNhoodSizeHist
    thy.milo <- buildGraph(thy.milo, k = 11, d = 40)
    thy.milo <- makeNhoods(
        thy.milo,
        prop = 0.2,
        k = 11,
        d = 40,
        refined = TRUE,
        refinement_scheme = "graph"
    )
    colData(thy.milo)$Sample <- paste(
        colData(thy.milo)$SortDay,
        colData(thy.milo)$Age,
        sep = "_"
    )
    thy.milo <- countCells(
        thy.milo,
        meta.data = data.frame(colData(thy.milo)),
        samples = "Sample"
    )
    plotNhoodSizeHist(thy.milo)


    # --- Differential Abundance Testing [] ---
    # Key functions: testNhoods
    thy.design <- data.frame(colData(thy.milo))[, c("Sample", "SortDay", "Age")]
    thy.design <- dplyr::distinct(thy.design)
    rownames(thy.design) <- thy.design$Sample
    thy.design <- thy.design[colnames(nhoodCounts(thy.milo)), , drop = FALSE]
    contrast.1 <- c("Age1wk - Age4wk")
    da_results <- testNhoods(
        thy.milo,
        design = ~ 0 + Age,
        design.df = thy.design,
        model.contrasts = contrast.1,
        fdr.weighting = "graph-overlap",
        norm.method = "TMM"
    )


    # --- Neighborhood Graph Visualization [] ---
    # Key functions: buildNhoodGraph, plotNhoodGraphDA
    thy.milo <- buildNhoodGraph(thy.milo)
    plotNhoodGraphDA(
        thy.milo,
        da_results,
        alpha = 0.1
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_milor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_milor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_milor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MILOR:", paste0("    milor: ", packageVersion("miloR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_milor_results.csv
    touch ${prefix}_milor_output.rds
    echo "BIOC_MILOR:" > versions.yml
    echo "    milor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MILOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_MILOR(ch_input)

    emit:
    results  = BIOC_MILOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MILOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MILOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MILOR.out.versions  // channel: path(versions.yml)
}
