#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cBioPortalData
// The cBioPortalData R package accesses study datasets from the cBio Cancer Genomics Portal. It access
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cBioPortalData/inst/doc/cBioPortalData.R
// Upstream  : AnVIL, survival, survminer
// Downstream: bioCancer, canceR
//
// Install: BiocManager::install("cBioPortalData")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_CBIOPORTALDATA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cbioportaldata"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cbioportaldata_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cbioportaldata_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cbioportaldata_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Surv", "jsonlite", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    library(SummarizedExperiment)
    }
    library(Surv)
    library(jsonlite)

    # --- Cbioportal [] ---
    # Key functions: cBioPortal, getStudies
    ---------------------------------------------------------------------
    cbio <- cBioPortal()
    studies <- getStudies(cbio, buildReport = TRUE)
    head(studies)
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    metadata(acc)
    # --- Table [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    table(colData(laml)\$OS_STATUS)
    class(colData(laml)\$OS_MONTHS)
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    collaml <- colData(laml)
    collaml[collaml\$OS_MONTHS == "[Not Available]", "OS_MONTHS"] <- NA
    collaml\$OS_MONTHS <- as.numeric(collaml\$OS_MONTHS)
    colData(laml) <- collaml
    # --- Survfit [] ---
    # Key functions: survfit, Surv, colData, ggsurvplot
    ---------------------------------------------------------------------
    fit <- survfit(
        Surv(OS_MONTHS, as.numeric(substr(OS_STATUS, 1, 1))) ~ SEX,
        data = colData(laml)
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
        write.csv(as.data.frame(.main), "${prefix}_cbioportaldata_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_cbioportaldata_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_cbioportaldata_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CBIOPORTALDATA:", paste0("    cbioportaldata: ", as.character(packageVersion("cBioPortalData")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cbioportaldata_results.csv
    touch ${prefix}_cbioportaldata_output.rds
    echo "BIOC_CBIOPORTALDATA:" > versions.yml
    echo "    cbioportaldata: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CBIOPORTALDATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CBIOPORTALDATA(ch_input)

    emit:
    results  = BIOC_CBIOPORTALDATA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CBIOPORTALDATA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CBIOPORTALDATA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CBIOPORTALDATA.out.versions  // channel: path(versions.yml)
}
