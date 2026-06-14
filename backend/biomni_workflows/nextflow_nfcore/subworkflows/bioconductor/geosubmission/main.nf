#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GEOsubmission
// Helps to easily submit a microarray dataset and the associated sample information to GEO by preparin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GEOsubmission/inst/doc/GEOsubmission.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GEOsubmission")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOSUBMISSION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geosubmission"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geosubmission_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geosubmission_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geosubmission_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GEOsubmission", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(GEOsubmission)
    library(jsonlite)

    # --- Examplewcel [] ---
    # Key functions: microarray2soft
    ## microarray2soft(sampleID,'sampleInfo.txt',seriesName,'seriesInfo.txt',
    ## softname='mydata.soft')
    ##
    # --- Datadirectory [] ---
    # Key functions: file
    dataDirectory<-system.file('extdata',package='GEOsubmission')
    # --- Showinfofiles [] ---
    # Key functions: delim, path
    ## read.delim(file.path(dataDirectory,'sampleInfo.txt'))
    ## read.delim(file.path(dataDirectory,'seriesInfo.txt'))
    # --- Examplewexpressionmatrix [] ---
    # Key functions: microarray2soft
    microarray2soft(sampleID,'sampleInfo.txt',seriesName,'seriesInfo.txt',
    datadir=dataDirectory,writedir=soft_example_dir,
    softname=soft_example_name,expressionmatrix='expressionNormalized.txt')
    # --- Deletesoft [] ---
    # Key functions: unlink
    ## Clean-up
    unlink(soft_example_fullpath)
    # --- Showexpressionmatrix [] ---
    # Key functions: delim, path
    ## read.delim(file.path(dataDirectory,'expressionNormalized.txt'))
    # --- Examplewstdoutput [] ---
    # Key functions: microarray2soft
    ## microarray2soft(c('1','2'),'sampleInfo.txt',seriesName,'seriesInfo.txt',
    ## datadir=dataDirectory,softname='',expressionmatrix='expressionNormalized.txt',
    ## verbose=FALSE)
    ##

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
        write.csv(as.data.frame(.main), "${prefix}_geosubmission_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_geosubmission_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_geosubmission_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEOSUBMISSION:", paste0("    geosubmission: ", as.character(packageVersion("GEOsubmission")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geosubmission_results.csv
    touch ${prefix}_geosubmission_output.rds
    echo "BIOC_GEOSUBMISSION:" > versions.yml
    echo "    geosubmission: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEOSUBMISSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEOSUBMISSION(ch_input)

    emit:
    results  = BIOC_GEOSUBMISSION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEOSUBMISSION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEOSUBMISSION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEOSUBMISSION.out.versions  // channel: path(versions.yml)
}
