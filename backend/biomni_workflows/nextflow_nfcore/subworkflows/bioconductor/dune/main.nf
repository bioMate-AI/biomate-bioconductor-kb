#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Dune
// Given a set of clustering labels, Dune merges pairs of clusters to increase mean ARI between labels,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Dune/inst/doc/Dune.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Dune")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DUNE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dune"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dune:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dune:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dune_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dune_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dune_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ARItrend)
    library(ConfusionPlot)
    library(Dune)
    library(jsonlite)

    # --- Ggplot [] ---
    # Key functions: ggplot, aes, geom_point
    ---------------------------------------------------------------------
    ggplot(nuclei, aes(x = x, y = y, col = subclass_label)) +
      geom_point()
    # --- Plotaris [] ---
    # Key functions: plotARIs, select
    ---------------------------------------------------------------------
    plotARIs(nuclei %>% select(SC3, Seurat, Monocle))
    # --- Dune [] ---
    # Key functions: Dune, select
    ---------------------------------------------------------------------
    merger <- Dune(clusMat = nuclei %>% select(SC3, Seurat, Monocle), verbose = TRUE)
    # --- Plotaris [] ---
    # Key functions: plotARIs
    ---------------------------------------------------------------------
    plotARIs(clusMat = merger$currentMat)
    # --- Plotprepost [] ---
    # Key functions: plotPrePost
    ---------------------------------------------------------------------
    plotPrePost(merger)
    # --- Confusionplot [] ---
    # Key functions: ConfusionPlot, labs
    ---------------------------------------------------------------------
    ConfusionPlot(merger$initialMat[, "SC3"], merger$currentMat[, "SC3"]) +
      labs(x = "Before merging", y = "After merging")
    # --- Aritrend [] ---
    # Key functions: ARItrend
    ---------------------------------------------------------------------
    ARItrend(merger)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dune_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dune_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dune_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DUNE:", paste0("    dune: ", packageVersion("Dune"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dune_results.csv
    touch ${prefix}_dune_output.rds
    echo "BIOC_DUNE:" > versions.yml
    echo "    dune: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DUNE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DUNE(ch_input)

    emit:
    results  = BIOC_DUNE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DUNE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DUNE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DUNE.out.versions  // channel: path(versions.yml)
}
