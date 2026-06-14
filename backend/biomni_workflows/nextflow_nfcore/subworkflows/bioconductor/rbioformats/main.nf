#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RBioFormats
// An R package which interfaces the OME Bio-Formats Java library to allow reading of proprietary micro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RBioFormats/inst/doc/RBioFormats.R
// Upstream  : EBImage, xml2
// Downstream: none
//
// Install: BiocManager::install("RBioFormats")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_RBIOFORMATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbioformats"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbioformats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbioformats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbioformats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("RBioFormats", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(RBioFormats)
    library(jsonlite)

    # --- Image Loading and Inspection [] ---
    # Key functions: read.image, dimorder
    img_file <- system.file("images", "sample.png", package = "EBImage")
    img <- read.image(img_file)
    img_dims <- dim(img)
    img_order <- dimorder(img)

    # --- Metadata Extraction [] ---
    # Key functions: read.metadata, metadata, coreMetadata
    img_file <- system.file("images", "nuclei.tif", package = "EBImage")
    meta_direct <- read.metadata(img_file)
    img <- read.image(img_file)
    meta_from_img <- metadata(img)
    core_meta <- coreMetadata(img)

    # --- OME-XML Metadata Parsing [] ---
    # Key functions: read.omexml
    img_file <- system.file("images", "nuclei.tif", package = "EBImage")
    xml_data <- read.omexml(img_file)

    # --- Mock Image Generation and Validation [] ---
    # Key functions: mockFile, read.image
    mock_path <- mockFile(
        sizeX = 256,
        sizeY = 256,
        pixelType = "uint16"
    )
    mock_img <- read.image(mock_path)
    mock_dims <- dim(mock_img)


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
        write.csv(as.data.frame(.main), "${prefix}_rbioformats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_rbioformats_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_rbioformats_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBIOFORMATS:", paste0("    rbioformats: ", as.character(packageVersion("RBioFormats")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbioformats_results.csv
    touch ${prefix}_rbioformats_output.rds
    echo "BIOC_RBIOFORMATS:" > versions.yml
    echo "    rbioformats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBIOFORMATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBIOFORMATS(ch_input)

    emit:
    results  = BIOC_RBIOFORMATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBIOFORMATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBIOFORMATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBIOFORMATS.out.versions  // channel: path(versions.yml)
}
