#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ReportingTools
// The ReportingTools software package enables users to easily display reports of analysis results gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ReportingTools/inst/doc/basicReportingTools.R
// Upstream  : ALL, Category, DESeq2, GOstats, GSEABase
// Downstream: none
//
// Install: BiocManager::install("ReportingTools")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_REPORTINGTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-reportingtools"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_reportingtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_reportingtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_reportingtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ReportingTools", "CSVFile", "HTMLReport", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(ReportingTools)
    library(CSVFile)
    library(HTMLReport)
    library(jsonlite)

    # --- Report Initialization [] ---
    # Key functions: HTMLReport
    report <- HTMLReport(
        shortName = "de_report",
        title = "Differential Expression Analysis Report",
        reportDirectory = "reports"
    )

    # --- Publishing Tabular Data [] ---
    # Key functions: publish
    my.df <- data.frame(
        EGID = c("103", "104", "105", "106", "107"),
        RPKM = c(4, 5, 3, 100, 75),
        DE = c("Yes", "Yes", "No", "No", "No")
    )
    publish(
        object = my.df,
        htmlRep = report,
        tableId = "expression_table"
    )

    # --- Adding Hyperlinks [] ---
    # Key functions: Link, publish
    gene_ids <- c("103", "104", "105", "106", "107")
    gene_links <- Link(
        ids = gene_ids,
        base = "https://www.ncbi.nlm.nih.gov/gene/"
    )
    linked.df <- data.frame(
        Gene = gene_links,
        RPKM = c(4, 5, 3, 100, 75)
    )
    publish(
        object = linked.df,
        htmlRep = report,
        tableId = "linked_table"
    )

    # --- Finalizing Report [] ---
    # Key functions: finish
    finish(
        htmlRep = report
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
        write.csv(as.data.frame(.main), "${prefix}_reportingtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_reportingtools_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_reportingtools_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_REPORTINGTOOLS:", paste0("    reportingtools: ", as.character(packageVersion("ReportingTools")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reportingtools_results.csv
    touch ${prefix}_reportingtools_output.rds
    echo "BIOC_REPORTINGTOOLS:" > versions.yml
    echo "    reportingtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REPORTINGTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REPORTINGTOOLS(ch_input)

    emit:
    results  = BIOC_REPORTINGTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REPORTINGTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REPORTINGTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REPORTINGTOOLS.out.versions  // channel: path(versions.yml)
}
