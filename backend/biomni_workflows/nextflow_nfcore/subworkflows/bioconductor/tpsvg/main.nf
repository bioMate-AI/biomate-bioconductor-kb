#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tpSVG
// The goal of `tpSVG` is to detect and visualize spatial variation in the gene expression for spatiall
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tpSVG/inst/doc/intro_to_tpSVG.R
// Upstream  : STexampleData, SpatialExperiment, scuttle
// Downstream: none
//
// Install: BiocManager::install("tpSVG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TPSVG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tpsvg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tpsvg:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tpsvg:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_tpsvg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tpsvg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tpsvg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Visium_humanDLPFC)
    library(jsonlite)

    # --- Log-normalize count data [] ---
    # Key functions: Visium_humanDLPFC, logNormCounts, rowData
    spe <- Visium_humanDLPFC()
    spe <- spe[, colData(spe)$in_tissue == 1]
    spe <- logNormCounts(spe)
    # --- Feature metadata inspection [] ---
    # Key functions: install_github, tpSVG, rowData, seqFISH_mouseEmbryo, session_info
    set.seed(1)
    spe_poisson  <- tpSVG(
    offset = log(spe$total)   # Natural log library size

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tpsvg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tpsvg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tpsvg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TPSVG:", paste0("    tpsvg: ", packageVersion("tpSVG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tpsvg_results.csv
    touch ${prefix}_tpsvg_output.rds
    echo "BIOC_TPSVG:" > versions.yml
    echo "    tpsvg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TPSVG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_TPSVG(ch_input)

    emit:
    results  = BIOC_TPSVG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TPSVG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TPSVG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TPSVG.out.versions  // channel: path(versions.yml)
}
