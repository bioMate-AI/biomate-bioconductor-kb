#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: LoomExperiment
// The LoomExperiment package provide a means to easily convert the Bioconductor "Experiment" classes t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/LoomExperiment/inst/doc/LoomExperiment.R
// Upstream  : none
// Downstream: OSCA.intro
//
// Install: BiocManager::install("LoomExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LOOMEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-loomexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-loomexperiment:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-loomexperiment:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_loomexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_loomexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_loomexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(LoomExperiment)
    library(LoomGraph)
    library(LoomGraphs)
    library(SingleCellExperiment)
    library(SingleCellLoomExperiment)
    library(jsonlite)

    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment, SingleCellLoomExperiment, LoomExperiment
    library(LoomExperiment)
    counts <- matrix(rpois(100, lambda = 10), ncol=10, nrow=10)
    sce <- SingleCellExperiment(assays = list(counts = counts))
    # --- Single Cell Loom Experiment [] ---
    # Key functions: SingleCellLoomExperiment
    scle <- SingleCellLoomExperiment(assays = list(counts = counts))
    # --- load l1 [] ---
    # Key functions: import
    system.file("extdata", "L1_DRG_20_example.loom", package = "LoomExperiment")
    scle <- import(l1_file, type="SingleCellLoomExperiment")
    # --- construct LoomGraph [] ---
    # Key functions: DataFrame, LoomGraph
    a <- c(1, 2, 3)
    b <- c(3, 2, 1)
    w <- c(100, 10, 1)
    # --- construct LoomGraphs [] ---
    # Key functions: LoomGraphs
    lgs <- LoomGraphs(lg, lg)
    names(lgs) <- c('lg1', 'lg2')
    # --- get col row graphs [] ---
    # Key functions: colGraphs, rowGraphs
    colGraphs(scle)
    rowGraphs(scle)
    # --- replace LoomGraphs [] ---
    # Key functions: colGraphs, rowGraphs
    colGraphs(scle) <- lgs
    rowGraphs(scle) <- lgs
    colGraphs(scle)
    # --- subset LoomExperiment [] ---
    # Key functions: colGraphs, rowGraphs
    scle2 <- scle[c(1, 3), 1:2]
    colGraphs(scle2)[[1]]
    rowGraphs(scle2)[[1]]
    # --- rbind LoomExperiment [] ---
    # Key functions: colGraphs, rowGraphs
    scle3 <- rbind(scle, scle)
    colGraphs(scle3)
    rowGraphs(scle3)
    # --- export LoomExperiment [] ---
    # Key functions: tempfile, export
    temp <- tempfile(fileext='.loom')
    export(scle2, temp)
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_loomexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_loomexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_loomexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LOOMEXPERIMENT:", paste0("    loomexperiment: ", packageVersion("LoomExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_loomexperiment_results.csv
    touch ${prefix}_loomexperiment_output.rds
    echo "BIOC_LOOMEXPERIMENT:" > versions.yml
    echo "    loomexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LOOMEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_LOOMEXPERIMENT(ch_input)

    emit:
    results  = BIOC_LOOMEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LOOMEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LOOMEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LOOMEXPERIMENT.out.versions  // channel: path(versions.yml)
}
