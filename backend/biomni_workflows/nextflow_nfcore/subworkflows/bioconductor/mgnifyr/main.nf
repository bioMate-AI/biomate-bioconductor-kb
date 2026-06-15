#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MGnifyR
// Utility package to facilitate integration and analysis of EBI MGnify data in R. The package can be u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MGnifyR/inst/doc/MGnifyR.R
// Upstream  : Biostrings, ggplot2, knitr, mia, miaViz
// Downstream: none
//
// Install: BiocManager::install("MGnifyR")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_MGNIFYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mgnifyr"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mgnifyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mgnifyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mgnifyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("MGnifyR", "MgnifyClient", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(MGnifyR)
    library(MgnifyClient)
    library(jsonlite)

    # --- Client Initialization and Study Search [] ---
    # Key functions: MgnifyClient, searchAnalysis
    mg <- MgnifyClient(useCache = TRUE)
    study_accession <- "MGYS00005058"
    analyses_accessions <- searchAnalysis(
        client = mg,
        type = "study",
        accession = study_accession
    )

    # --- Metadata Retrieval [] ---
    # Key functions: getMetadata
    mg <- MgnifyClient(useCache = TRUE)
    analyses_metadata <- getMetadata(
        client = mg,
        accession = analyses_accessions
    )

    # --- Fetching Microbiome Data [] ---
    # Key functions: getMicrobiomeData
    mg <- MgnifyClient(useCache = TRUE)
    mae <- getMicrobiomeData(
        client = mg,
        accession = analyses_accessions
    )

    # --- Download URL Retrieval and File Download [] ---
    # Key functions: searchFile, getFile
    mg <- MgnifyClient(useCache = TRUE)
    dl_urls <- searchFile(
        client = mg,
        accession = "MGYS00005058"
    )
    target_urls <- dl_urls[
        dl_urls\$attributes.description.label == "Predicted alpha tmRNA",
    ]
    cached_location <- getFile(
        client = mg,
        url = target_urls\$links.self[1]
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
        write.csv(as.data.frame(.main), "${prefix}_mgnifyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_mgnifyr_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_mgnifyr_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_MGNIFYR:", paste0("    mgnifyr: ", as.character(packageVersion("MGnifyR")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mgnifyr_results.csv
    touch ${prefix}_mgnifyr_output.rds
    echo "BIOC_MGNIFYR:" > versions.yml
    echo "    mgnifyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MGNIFYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MGNIFYR(ch_input)

    emit:
    results  = BIOC_MGNIFYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MGNIFYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MGNIFYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MGNIFYR.out.versions  // channel: path(versions.yml)
}
