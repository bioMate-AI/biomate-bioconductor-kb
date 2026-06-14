#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MuData
// Save MultiAssayExperiments to h5mu files supported by muon and mudata. Muon is a Python framework fo
//
// Input: input.rds (serialized MultiAssayExperiment to be exported to an .h5mu file)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MuData/inst/doc/Blood-CITE-seq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MuData")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MUDATA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mudata"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mudata_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mudata_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mudata_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MuData", "MultiAssayExperiment", "SummarizedExperiment", "rhdf5", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(MuData)
    library(MultiAssayExperiment)
    library(SummarizedExperiment)
    library(rhdf5)
    library(jsonlite)

    # --- Load user-provided input ---
    # input.rds: a serialized MultiAssayExperiment containing the modalities to
    #            export (e.g. RNA / ADT / HTO assays from a CITE-seq experiment).
    #            The object is written to an .h5mu file readable by muon / mudata.
    mae <- readRDS("input.rds")
    if (!is(mae, "MultiAssayExperiment")) {
      stop("input.rds must contain a MultiAssayExperiment object")
    }
    experiment_dims <- lapply(experiments(mae), dim)

    # --- write H5 M U [] ---
    # Key functions: writeH5MU
    writeH5MU(mae, "citefuse_example.h5mu")

    # --- H5 Fopen [] ---
    # Key functions: H5Fopen, h5ls, H5Gopen
    h5 <- rhdf5::H5Fopen("citefuse_example.h5mu")
    mods <- h5ls(H5Gopen(h5, "mod"), recursive = FALSE)
    rhdf5::H5close()

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
        write.csv(as.data.frame(.main), "${prefix}_mudata_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_mudata_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_mudata_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUDATA:", paste0("    mudata: ", as.character(packageVersion("MuData")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mudata_results.csv
    touch ${prefix}_mudata_output.rds
    echo "BIOC_MUDATA:" > versions.yml
    echo "    mudata: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUDATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MUDATA(ch_input)

    emit:
    results  = BIOC_MUDATA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUDATA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUDATA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUDATA.out.versions  // channel: path(versions.yml)
}
