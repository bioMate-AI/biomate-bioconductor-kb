#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: zellkonverter
// Provides methods to convert between Python AnnData objects and SingleCellExperiment objects. These a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/zellkonverter/inst/doc/zellkonverter.R
// Upstream  : scRNAseq, basilisk
// Downstream: scATAC.Explorer, OSCA.intro
//
// Install: BiocManager::install("zellkonverter")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ZELLKONVERTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-zellkonverter"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_zellkonverter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_zellkonverter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_zellkonverter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("zellkonverter", "AnnData2SCE", "AnnDataDependencies", "SCE2AnnData", "SegerstolpePancreasData", "ZeiselBrainData", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(zellkonverter)
    library(AnnData2SCE)
    library(AnnDataDependencies)
    library(SCE2AnnData)
    library(SegerstolpePancreasData)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- Import H5AD Data [] ---
    # Key functions: readH5AD
    example_h5ad <- system.file(
        "extdata", "krumsiek11.h5ad",
        package = "zellkonverter"
    )
    sce <- readH5AD(
        file = example_h5ad,
        verbose = TRUE
    )

    # --- Export SingleCellExperiment Data [] ---
    # Key functions: writeH5AD
    out_path <- tempfile(
        pattern = "output",
        fileext = ".h5ad"
    )
    writeH5AD(
        sce = sce,
        file = out_path,
        verbose = TRUE
    )

    # --- Convert SingleCellExperiment to AnnData [] ---
    # Key functions: SCE2AnnData, zellkonverterAnnDataEnv
    adata <- basilisk::basiliskRun(
        fun = function(x) {
            SCE2AnnData(x)
        },
        env = zellkonverterAnnDataEnv(),
        x = sce
    )

    # --- Convert AnnData to SingleCellExperiment [] ---
    # Key functions: AnnData2SCE, zellkonverterAnnDataEnv
    sce_back <- basilisk::basiliskRun(
        fun = function(x) {
            AnnData2SCE(x)
        },
        env = zellkonverterAnnDataEnv(),
        x = adata
    )

    # --- Check Environment Dependencies [] ---
    # Key functions: AnnDataDependencies
    deps <- AnnDataDependencies(
        version = "0.7.6"
    )


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
        write.csv(as.data.frame(.main), "${prefix}_zellkonverter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_zellkonverter_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_zellkonverter_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ZELLKONVERTER:", paste0("    zellkonverter: ", as.character(packageVersion("zellkonverter")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zellkonverter_results.csv
    touch ${prefix}_zellkonverter_output.rds
    echo "BIOC_ZELLKONVERTER:" > versions.yml
    echo "    zellkonverter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ZELLKONVERTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ZELLKONVERTER(ch_input)

    emit:
    results  = BIOC_ZELLKONVERTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ZELLKONVERTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ZELLKONVERTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ZELLKONVERTER.out.versions  // channel: path(versions.yml)
}
