#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cydar
// Identifies differentially abundant populations between samples and groups in mass cytometry data. Pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cydar/inst/doc/cydar.R
// Upstream  : edgeR, flowCore, knitr, ncdfFlow
// Downstream: none
//
// Install: BiocManager::install("cydar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYDAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cydar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cydar:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cydar:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_cydar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cydar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cydar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cydar)
    library(DGEList)
    library(Subset)
    library(jsonlite)

    # --- Cell Data Preparation and Counting [] ---
    # Key functions: prepareCellData, countCells
    cd <- prepareCellData(processed.exprs)
    cd <- countCells(cd, tol = 0.5)


    # --- Spatial FDR and Sphere Selection [] ---
    # Key functions: spatialFDR, findFirstSphere, intensityRanges
    qvals <- spatialFDR(intensities(cd), res$table$PValue)
    nonred <- findFirstSphere(intensities(cd), res$table$PValue)
    limits <- intensityRanges(cd, p = 0.05)


    # --- Visualisation of Sphere Intensities [] ---
    # Key functions: plotSphereLogFC, plotSphereIntensity, interpretSpheres
    plotSphereLogFC(coords$x[, 1], coords$x[, 2], sig.res$logFC)
    plotSphereIntensity(
        coords$x[, 1], coords$x[, 2], sig.coords[, 1],
        irange = limits[, 1], main = "Marker1"
    )
    app <- interpretSpheres(
        cd, select = nonred, metrics = res$table, run = FALSE,
        red.coords = all.coords$x[, 1:2], red.highlight = is.sig
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cydar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cydar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cydar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYDAR:", paste0("    cydar: ", packageVersion("cydar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cydar_results.csv
    touch ${prefix}_cydar_output.rds
    echo "BIOC_CYDAR:" > versions.yml
    echo "    cydar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYDAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_CYDAR(ch_input)

    emit:
    results  = BIOC_CYDAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYDAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYDAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYDAR.out.versions  // channel: path(versions.yml)
}
