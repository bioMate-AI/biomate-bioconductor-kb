#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SiPSiC
// Infer biological pathway activity of cells from single-cell RNA-sequencing data by calculating a pat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SiPSiC/inst/doc/SiPSiC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SiPSiC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIPSIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sipsic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sipsic:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sipsic:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_sipsic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sipsic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sipsic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Example [] ---
    # Key functions: SingleCellExperiment, getPathwayScores
    library(SiPSiC)
    geneCountsMatrix <- matrix(rpois(16, lambda = 10), ncol = 4, nrow = 4)
    geneCountsMatrix <- as(geneCountsMatrix, "dgCMatrix")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sipsic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sipsic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sipsic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIPSIC:", paste0("    sipsic: ", packageVersion("SiPSiC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sipsic_results.csv
    touch ${prefix}_sipsic_output.rds
    echo "BIOC_SIPSIC:" > versions.yml
    echo "    sipsic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIPSIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_SIPSIC(ch_input)

    emit:
    results  = BIOC_SIPSIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIPSIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIPSIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIPSIC.out.versions  // channel: path(versions.yml)
}
