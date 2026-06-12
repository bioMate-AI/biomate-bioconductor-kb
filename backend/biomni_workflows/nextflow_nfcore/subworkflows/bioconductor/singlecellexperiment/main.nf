#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SingleCellExperiment
// Defines a S4 class for storing data from single-cell experiments. This includes specialized methods 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SingleCellExperiment/inst/doc/devel.R
// Upstream  : scRNAseq, Rtsne
// Downstream: alabaster.sce, BASiCS, batchelor, BayesSpace, CATALYST
//
// Install: BiocManager::install("SingleCellExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SINGLECELLEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singlecellexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_singlecellexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singlecellexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singlecellexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("AsetX", "jsonlite", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
     library(SummarizedExperiment)
   }
    library(AsetX)
    library(jsonlite)

    # --- Object Construction [] ---
    # Key functions: SingleCellExperiment, assays, colData, rowData
    counts <- matrix(rpois(1000, lambda = 10), ncol = 20, nrow = 50)
    coldata <- DataFrame(Treatment = rep(c("Chirp", "Mute"), each = 10))
    rowdata <- DataFrame(GeneType = rep(c("Protein", "RNA"), length.out = 50))
    sce <- SingleCellExperiment(
        assays = list(counts = counts),
        colData = coldata,
        rowData = rowdata
    )

    # --- Metadata Annotation [] ---
    # Key functions: colData, rowData, sizeFactors, sizeFactors<-
    colData(sce)\$CellType <- sample(
        c("T-cell", "B-cell"), 
        ncol(sce), 
        replace = TRUE
    )
    rowData(sce)\$Length <- runif(nrow(sce), 100, 5000)
    sf <- colSums(assay(sce, "counts"))
    sizeFactors(sce) <- sf / mean(sf)

    # --- Dimensionality Reduction [] ---
    # Key functions: reducedDim, reducedDim<-, reducedDims, reducedDimNames
    pca_data <- matrix(runif(ncol(sce) * 5), ncol = 5)
    tsne_data <- matrix(runif(ncol(sce) * 2), ncol = 2)
    reducedDim(sce, "PCA") <- pca_data
    reducedDim(sce, "TSNE") <- tsne_data
    red_names <- reducedDimNames(sce)

    # --- Alternative Experiments [] ---
    # Key functions: altExp, altExp<-, altExpNames, altExps
    spike_counts <- matrix(rpois(100, lambda = 5), ncol = ncol(sce), nrow = 5)
    spike_se <- SingleCellExperiment(assays = list(counts = spike_counts))
    altExp(sce, "ERCC") <- spike_se
    alt_names <- altExpNames(sce)

    # --- Internal Metadata Management [] ---
    # Key functions: int_colData, int_elementMetadata, int_metadata
    int_colData(sce)\$A <- DataFrame(X = runif(ncol(sce)))
    int_elementMetadata(sce)\$A <- DataFrame(Y = runif(nrow(sce)))
    int_metadata(sce)\$A <- list(Z = "Aaron")


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
        write.csv(as.data.frame(.main), "${prefix}_singlecellexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_singlecellexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_singlecellexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGLECELLEXPERIMENT:", paste0("    singlecellexperiment: ", as.character(packageVersion("SingleCellExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singlecellexperiment_results.csv
    touch ${prefix}_singlecellexperiment_output.rds
    echo "BIOC_SINGLECELLEXPERIMENT:" > versions.yml
    echo "    singlecellexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGLECELLEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_SINGLECELLEXPERIMENT(ch_input)

    emit:
    results  = BIOC_SINGLECELLEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGLECELLEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGLECELLEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGLECELLEXPERIMENT.out.versions  // channel: path(versions.yml)
}
