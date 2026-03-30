#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: hpar
// The hpar package provides a simple R interface to and data from the Human Protein Atlas project.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/hpar/inst/doc/hpar.R
// Upstream  : BiocStyle, ExperimentHub, dplyr
// Downstream: none
//
// Install: BiocManager::install("hpar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HPAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hpar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hpar:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hpar:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hpar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hpar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hpar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(hpar)
    library(jsonlite)

    # --- all Hpar Data [] ---
    # Key functions: allHparData
    library("hpar")
    hpa_data <- allHparData()
    # --- count [] ---
    # Key functions: count, arrange
    names(normtissue)
    length(unique(normtissue$Gene))
    length(unique(normtissue$Cell.type))
    # --- hpa Subcellular Loc [] ---
    # Key functions: hpaSubcellularLoc, rnaGeneCellLine, full_join
    subcell <- hpaSubcellularLoc()
    rna <- rnaGeneCellLine()
    filter(normtissue, Gene == id) |>
    # --- get Hpa Version [] ---
    # Key functions: getHpaVersion, getHpaDate, getHpaEnsembl
    getHpaVersion()
    getHpaDate()
    getHpaEnsembl()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hpar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hpar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hpar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HPAR:", paste0("    hpar: ", packageVersion("hpar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hpar_results.csv
    touch ${prefix}_hpar_output.rds
    echo "BIOC_HPAR:" > versions.yml
    echo "    hpar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HPAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HPAR(ch_input)

    emit:
    results  = BIOC_HPAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HPAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HPAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HPAR.out.versions  // channel: path(versions.yml)
}
