#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpatialExperiment
// Defines an S4 class for storing data from spatial -omics experiments. The class extends SingleCellEx
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpatialExperiment/inst/doc/SpatialExperiment.R
// Upstream  : BumpyMatrix
// Downstream: alabaster.spatial, ExperimentSubset, imcRtools, SPIAT, tidySpatialExperiment
//
// Install: BiocManager::install("SpatialExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SPATIALEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spatialexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spatialexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spatialexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spatialexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SpatialExperiment", "jsonlite", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    lib    library(SummarizedExperiment)
rary(SpatialExperiment)
    library(jsonlite)

    # --- Import 10x Visium Data [] ---
    # Key functions: read10xVisium
    dir <- system.file(
        file.path("extdata", "10xVisium"),
        package = "SpatialExperiment"
    )
    sample_ids <- c("section1", "section2")
    samples <- file.path(dir, sample_ids, "outs")
    spe10x <- read10xVisium(
        samples, sample_ids,
        type = "sparse", data = "raw",
        images = "lowres", load = FALSE
    )

    # --- Custom Object Construction [] ---
    # Key functions: SpatialExperiment
    n <- 10
    m <- 20
    y <- matrix(rnorm(n * m), nrow = n, ncol = m)
    cd <- S4Vectors::DataFrame(x = seq(m), y = seq(m))
    xy <- matrix(runif(m * 2), nrow = m, ncol = 2)
    colnames(xy) <- c("x", "y")
    spe <- SpatialExperiment(
        assays = list(counts = y),
        colData = cd,
        spatialCoordsNames = c("x", "y"),
        spatialCoords = xy
    )

    # --- Spatial Coordinates Extraction [] ---
    # Key functions: spatialCoords, spatialCoordsNames
    coords <- spatialCoords(spe10x)
    coord_names <- spatialCoordsNames(spe10x)
    has_coords <- !isEmpty(spatialCoords(spe10x))

    # --- Image Data Management [] ---
    # Key functions: imgData, addImg, getImg, rmvImg
    url <- "https://i.redd.it/3pw5uah7xo041.jpg"
    spe_img <- addImg(
        spe10x,
        sample_id = "section1",
        image_id = "pomeranian",
        imageSource = url,
        scaleFactor = NA_real_,
        load = FALSE
    )
    img_list <- imgData(spe_img)
    spi <- getImg(spe_img, sample_id = "section1", image_id = "pomeranian")
    spe_clean <- rmvImg(spe_img, "section1", "pomeranian")

    # --- Subsetting and Merging [] ---
    # Key functions: colData, cbind
    sub_tissue <- spe10x[, colData(spe10x)\$in_tissue == 1]
    spe1 <- spe10x[, spe10x\$sample_id == "section1"]
    spe2 <- spe10x[, spe10x\$sample_id == "section2"]
    spe1\$sample_id <- paste(spe1\$sample_id, "A", sep = ".")
    spe2\$sample_id <- paste(spe2\$sample_id, "B", sep = ".")
    spe_combined <- cbind(spe1, spe2)


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
        write.csv(as.data.frame(.main), "${prefix}_spatialexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_spatialexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_spatialexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPATIALEXPERIMENT:", paste0("    spatialexperiment: ", as.character(packageVersion("SpatialExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatialexperiment_results.csv
    touch ${prefix}_spatialexperiment_output.rds
    echo "BIOC_SPATIALEXPERIMENT:" > versions.yml
    echo "    spatialexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPATIALEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPATIALEXPERIMENT(ch_input)

    emit:
    results  = BIOC_SPATIALEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPATIALEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPATIALEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPATIALEXPERIMENT.out.versions  // channel: path(versions.yml)
}
