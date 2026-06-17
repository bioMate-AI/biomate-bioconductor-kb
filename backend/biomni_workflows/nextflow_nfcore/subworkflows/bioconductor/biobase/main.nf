#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Biobase
// Functions that are needed by many other packages or which replace R functions.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Biobase/inst/doc/BiobaseDevelopment.R
// Upstream  : BiocManager, convert
// Downstream: ACME, affy, affycomp, affyContam, affycoretools
//
// Install: BiocManager::install("Biobase")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BIOBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biobase"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biobase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biobase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biobase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(Biobase)
    library(jsonlite)

    # --- Data Loading and Inspection ---
    # Key functions: exprs, pData, fData, annotation, storageMode
    data(sample.ExpressionSet)
    expr_matrix <- exprs(sample.ExpressionSet)
    pheno_df <- pData(sample.ExpressionSet)
    feature_df <- fData(sample.ExpressionSet)
    annot <- annotation(sample.ExpressionSet)
    smode <- storageMode(sample.ExpressionSet)

    # --- Expression Data Transformation ---
    # Key functions: exprs, assayData, assayDataNew
    data(sample.ExpressionSet)
    raw_exprs <- exprs(sample.ExpressionSet)
    log_exprs <- log2(raw_exprs + 1)
    exprs(sample.ExpressionSet) <- log_exprs
    adata <- assayData(sample.ExpressionSet)

    # --- Metadata Manipulation ---
    # Key functions: phenoData, varMetadata, AnnotatedDataFrame, pData
    data(sample.ExpressionSet)
    pdata_obj <- phenoData(sample.ExpressionSet)
    var_meta <- varMetadata(pdata_obj)
    new_pdata <- AnnotatedDataFrame(
        data = pData(sample.ExpressionSet),
        varMetadata = var_meta
    )
    phenoData(sample.ExpressionSet) <- new_pdata

    # --- Object Versioning and Upgrades ---
    # Key functions: classVersion, isCurrent, updateObject
    data(sample.ExpressionSet)
    c_version <- classVersion(sample.ExpressionSet)
    current_status <- isCurrent(sample.ExpressionSet)
    updated_obj <- updateObject(sample.ExpressionSet)
    new_version <- classVersion(updated_obj)


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
        write.csv(as.data.frame(.main), "${prefix}_biobase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_biobase_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_biobase_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOBASE:", paste0("    biobase: ", as.character(packageVersion("Biobase")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biobase_results.csv
    touch ${prefix}_biobase_output.rds
    echo "BIOC_BIOBASE:" > versions.yml
    echo "    biobase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOBASE(ch_input)

    emit:
    results  = BIOC_BIOBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOBASE.out.versions  // channel: path(versions.yml)
}
