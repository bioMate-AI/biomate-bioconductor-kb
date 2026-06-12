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
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Getter", "McKellarMuscleData", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(Getter)
    library(McKellarMuscleData)
    library(jsonlite)

    # --- Quality control and filtering [] ---
    # Key functions: colData, annotPred, annotNPred, annotOp
    ---------------------------------------------------------------------
    # Get logical vector
    colData(sfe)\$in_tissue <- annotPred(sfe, colGeometryName = "spotPoly",
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
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_spatialfeatureexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_spatialfeatureexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_spatialfeatureexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALFEATUREEXPERIMENT:", paste0("    spatialfeatureexperiment: ", as.character(packageVersion("SpatialFeatureExperiment")))),
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
