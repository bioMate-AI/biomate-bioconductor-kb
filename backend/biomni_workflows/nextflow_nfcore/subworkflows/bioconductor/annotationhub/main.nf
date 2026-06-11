#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnnotationHub
// This package provides a client for the Bioconductor AnnotationHub web resource. The AnnotationHub we
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnnotationHub/inst/doc/AnnotationHub-HOWTO.R
// Upstream  : AnnotationDbi, Rsamtools, VariantAnnotation, txdbmaker
// Downstream: adductomicsR, AnnotationHubData, ExperimentHub, hipathia, ipdDb
//
// Install: BiocManager::install("AnnotationHub")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ANNOTATIONHUB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-annotationhub"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_annotationhub_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_annotationhub_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_annotationhub_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("AnnotationHub", "jsonlite", "AnnotationDbi", "txdbmaker", "Rsamtools")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(AnnotationHub)
    library(jsonlite)

    # --- Access AnnotationHub resources [] ---
    # Key functions: AnnotationHub, query
    library(AnnotationHub)
    ah <- AnnotationHub()
    query(ah, "OrgDb")
    # --- keytypes [] ---
    # Key functions: keytypes, columns
    library(AnnotationDbi)
    AnnotationDbi::keytypes(orgdb)
    AnnotationDbi::columns(orgdb)
    # --- query [] ---
    # Key functions: query
    query(ah, c("Takifugu", "release-94"))
    # --- make Tx Db From G Ranges [] ---
    # Key functions: makeTxDbFromGRanges
    library(txdbmaker)         # for makeTxDbFromGRanges
    txdb <- makeTxDbFromGRanges(gtf_subset)
    # --- exons [] ---
    # Key functions: exons, getSeq, query
    library(Rsamtools)               # for getSeq,FaFile-method
    exons <- exons(txdb)
    length(exons)

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
        write.csv(as.data.frame(.main), "${prefix}_annotationhub_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_annotationhub_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_annotationhub_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANNOTATIONHUB:", paste0("    annotationhub: ", as.character(packageVersion("AnnotationHub")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotationhub_results.csv
    touch ${prefix}_annotationhub_output.rds
    echo "BIOC_ANNOTATIONHUB:" > versions.yml
    echo "    annotationhub: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANNOTATIONHUB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANNOTATIONHUB(ch_input)

    emit:
    results  = BIOC_ANNOTATIONHUB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANNOTATIONHUB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANNOTATIONHUB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANNOTATIONHUB.out.versions  // channel: path(versions.yml)
}
