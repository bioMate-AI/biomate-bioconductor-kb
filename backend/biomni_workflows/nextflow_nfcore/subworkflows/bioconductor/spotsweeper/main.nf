#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpotSweeper
// Spatially-aware quality control (QC) software for both spot-level and artifact-level QC in spot-base
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpotSweeper/inst/doc/getting_started.R
// Upstream  : devtools, escheR, ggpubr
// Downstream: none
//
// Install: BiocManager::install("SpotSweeper")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPOTSWEEPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spotsweeper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spotsweeper:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spotsweeper:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spotsweeper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spotsweeper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spotsweeper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpotSweeper)
    library(Visium_humanDLPFC)
    library(jsonlite)

    # --- Spatial Artifact Identification [] ---
    # Key functions: findArtifacts
    spe <- findArtifacts(
        spe,
        mito_percent = "expr_chrM_ratio",
        mito_sum = "expr_chrM",
        n_rings = 5,
        name = "artifact"
    )


    # --- Quality Control Visualization [] ---
    # Key functions: plotQC
    p1 <- plotQC(spe, metric = "sum_log", outliers = "sum_outliers")
    p2 <- plotQC(spe, metric = "detected_log", outliers = "detected_outliers")
    p3 <- plotQC(spe, metric = "expr_chrM_ratio", outliers = "artifact")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spotsweeper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spotsweeper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spotsweeper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPOTSWEEPER:", paste0("    spotsweeper: ", packageVersion("SpotSweeper"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spotsweeper_results.csv
    touch ${prefix}_spotsweeper_output.rds
    echo "BIOC_SPOTSWEEPER:" > versions.yml
    echo "    spotsweeper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPOTSWEEPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPOTSWEEPER(ch_input)

    emit:
    results  = BIOC_SPOTSWEEPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPOTSWEEPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPOTSWEEPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPOTSWEEPER.out.versions  // channel: path(versions.yml)
}
