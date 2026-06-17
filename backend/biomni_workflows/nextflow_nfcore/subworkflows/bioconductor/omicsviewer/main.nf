#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omicsViewer
// omicsViewer visualizes ExpressionSet (or SummarizedExperiment) in an interactive way. The omicsViewe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omicsViewer/inst/doc/quickStart.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("omicsViewer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICSVIEWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicsviewer"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicsviewer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicsviewer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicsviewer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("omicsViewer", "NS", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(omicsViewer)
    library(NS)
    library(jsonlite)

    # --- Gene Set Annotation [] ---
    # Key functions: read_gmt, gsAnnotIdList
    packdir <- system.file("extdata", package = "omicsViewer")
    fd <- read.delim(file.path(packdir, "featureGeneral.tsv"))
    genesets <- read_gmt(
        file.path(packdir, "geneset.gmt"),
        data.frame = TRUE
    )
    gsannot <- gsAnnotIdList(
        idList = rownames(fd),
        gsIdMap = genesets,
        data.frame = FALSE
    )

    # --- Correlation Analysis and Metadata Extension [] ---
    # Key functions: correlationAnalysis, extendMetaData
    packdir <- system.file("extdata", package = "omicsViewer")
    drugData <- read.delim(file.path(packdir, "sampleDrug.tsv"))
    expr <- read.delim(file.path(packdir, "expressionMatrix.tsv"))
    drugcor <- correlationAnalysis(
        as.matrix(expr),
        pheno = drugData[, 1:2]
    )
    d <- readRDS("dtest.RDS")
    d_extended <- extendMetaData(
        d,
        drugcor,
        where = "fData"
    )

    # --- Shiny App Interface Setup [] ---
    # Key functions: app_ui, app_module
    ui <- shiny::fluidPage(
        app_ui("app")
    )
    server <- function(input, output, session) {
        shiny::callModule(
            app_module,
            id = "app",
            dir = shiny::reactive("path/to/obj")
        )
    }


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
        write.csv(as.data.frame(.main), "${prefix}_omicsviewer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_omicsviewer_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_omicsviewer_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSVIEWER:", paste0("    omicsviewer: ", as.character(packageVersion("omicsViewer")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicsviewer_results.csv
    touch ${prefix}_omicsviewer_output.rds
    echo "BIOC_OMICSVIEWER:" > versions.yml
    echo "    omicsviewer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSVIEWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSVIEWER(ch_input)

    emit:
    results  = BIOC_OMICSVIEWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSVIEWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSVIEWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSVIEWER.out.versions  // channel: path(versions.yml)
}
