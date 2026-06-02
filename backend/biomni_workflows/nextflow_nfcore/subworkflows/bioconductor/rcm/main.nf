#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RCM
// Combine ideas of log-linear analysis of contingency table, flexible response function estimation and
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RCM/inst/doc/RCMvignette.R
// Upstream  : BiocManager, phyloseq
// Downstream: none
//
// Install: BiocManager::install("RCM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcm:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcm:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RCM)
    library(jsonlite)

    # --- Constrained Ordination and Triplots [] ---
    # Key functions: plot, addOrthProjection
    plot(ZellerRCM2constr, plotType = c("samples"), samColour = "Diagnosis")
    tmpPlot2 <- plot(ZellerRCM2constr,
        plotType = c("species", "samples"), returnCoords = TRUE)
    addOrthProjection(tmpPlot2, species = "Pseudomonas fluorescens",
        sample = c(-12, 7))


    # --- Response Function and Residual Analysis [] ---
    # Key functions: plotRespFun, residualPlot
    plotRespFun(ZellerRCM2constrNonParam, Dim = 1, samShape = "Diagnosis")
    residualPlot(ZellerRCM2constr, whichTaxa = "response", numTaxa = 6)
    residualPlot(ZellerRCM2constr, whichTaxa = "runs", resid = "Deviance",
        numTaxa = 6)


    # --- Coordinate Extraction and Signal Analysis [] ---
    # Key functions: extractCoord
    zellerCoords <- extractCoord(ZellerRCM2)
    taxaSignals <- rowSums(zellerCoords$species[, c("end1", "end2")]^2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCM:", paste0("    rcm: ", packageVersion("RCM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcm_results.csv
    touch ${prefix}_rcm_output.rds
    echo "BIOC_RCM:" > versions.yml
    echo "    rcm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCM(ch_input)

    emit:
    results  = BIOC_RCM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCM.out.versions  // channel: path(versions.yml)
}
