#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpatialFeatureExperiment
// A new S4 class integrating Simple Features with the R package sf to bring geospatial data analysis m
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpatialFeatureExperiment/inst/doc/SFE.R
// Upstream  : none
// Downstream: Voyager
//
// Install: BiocManager::install("SpatialFeatureExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPATIALFEATUREEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialfeatureexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spatialfeatureexperiment:1.8.6--r44_0' :
        'quay.io/biocontainers/bioconductor-spatialfeatureexperiment:1.8.6--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialfeatureexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialfeatureexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialfeatureexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Getter)
    library(McKellarMuscleData)
    library(jsonlite)

    # --- Quality control and filtering [] ---
    # Key functions: colData, annotPred, annotNPred, annotOp
    ---------------------------------------------------------------------
    # Get logical vector
    colData(sfe)$in_tissue <- annotPred(sfe, colGeometryName = "spotPoly",
                                        annotGeometryName = "tissueBoundary",
                                        sample_id = "Vis5A")
    # --- Dataset analysis [] ---
    # Key functions: dataset, McKellarMuscleData, polygons, dimGeometry, st_geometry, margin, dimGeometries, dimGeometryNames
    ---------------------------------------------------------------------
    # Convert regular data frame with coordinates to sf data frame
    cg <- df2sf(coords1[,c("col", "row")], c("col", "row"), spotDiameter = 0.7)
    rownames(cg) <- colnames(mat)
    sfe3 <- SpatialFeatureExperiment(list(counts = mat), colGeometries = list(foo = cg))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spatialfeatureexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spatialfeatureexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spatialfeatureexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALFEATUREEXPERIMENT:", paste0("    spatialfeatureexperiment: ", packageVersion("SpatialFeatureExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialfeatureexperiment_results.csv
    touch ${prefix}_spatialfeatureexperiment_output.rds
    echo "BIOC_SPATIALFEATUREEXPERIMENT:" > versions.yml
    echo "    spatialfeatureexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALFEATUREEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALFEATUREEXPERIMENT(ch_input)

    emit:
    results  = BIOC_SPATIALFEATUREEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALFEATUREEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALFEATUREEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALFEATUREEXPERIMENT.out.versions  // channel: path(versions.yml)
}
