#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Path2PPI
// Package to predict protein-protein interaction (PPI) networks in target organisms for which only a v
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Path2PPI/inst/doc/Path2PPI-tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Path2PPI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATH2PPI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-path2ppi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-path2ppi:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-path2ppi:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_path2ppi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_path2ppi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_path2ppi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Path2PPI)
    library(jsonlite)

    # --- Style Knitr [] ---
    # Key functions: markdown
    suppressPackageStartupMessages({
        library("Path2PPI")
    })
    BiocStyle::markdown()
    # --- Path2 P P I [] ---
    # Key functions: Path2PPI
    ---------------------------------------------------------------------
    ppi <- Path2PPI("Autophagy induction", "Podospora anserina", "5145")
    # --- Addreference [] ---
    # Key functions: addReference
    ---------------------------------------------------------------------
    ppi <- addReference(ppi, "Homo sapiens", "9606", human.ai.proteins,
                        human.ai.irefindex, pa2human.ai.homologs)
    # --- Addreference [] ---
    # Key functions: addReference, cerevisiae
    ---------------------------------------------------------------------
    ppi <- addReference(ppi, "Saccharomyces cerevisiae (S288c)", "559292",
                        yeast.ai.proteins, yeast.ai.irefindex,
                        pa2yeast.ai.homologs)
    # --- Showreferences [] ---
    # Key functions: showReferences
    ---------------------------------------------------------------------
    showReferences(ppi)
    # --- Predictppi [] ---
    # Key functions: predictPPI
    ---------------------------------------------------------------------
    ppi <- predictPPI(ppi,h.range=c(1e-60,1e-20))
    # --- Show [] ---
    # Key functions: show
    ---------------------------------------------------------------------
    ppi #show(ppi)
    # --- Showinteraction [] ---
    # Key functions: showInteraction
    ---------------------------------------------------------------------
    showInteraction(ppi,interaction=c("B2AT71","B2AE79"))
    # --- Getppi [] ---
    # Key functions: getPPI
    ---------------------------------------------------------------------
    my.ppi <- getPPI(ppi)
    my.ppi
    # --- Gethybridnetwork [] ---
    # Key functions: getHybridNetwork
    ---------------------------------------------------------------------
    my.hybrid <- getHybridNetwork(ppi)
    my.hybrid

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_path2ppi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_path2ppi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_path2ppi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATH2PPI:", paste0("    path2ppi: ", packageVersion("Path2PPI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_path2ppi_results.csv
    touch ${prefix}_path2ppi_output.rds
    echo "BIOC_PATH2PPI:" > versions.yml
    echo "    path2ppi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATH2PPI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATH2PPI(ch_input)

    emit:
    results  = BIOC_PATH2PPI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATH2PPI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATH2PPI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATH2PPI.out.versions  // channel: path(versions.yml)
}
