#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: basilisk
// Installs a self-contained conda instance that is managed by the R/Bioconductor installation machiner
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/basilisk/inst/doc/motivation.R
// Upstream  : BiocStyle, reticulate
// Downstream: scviR
//
// Install: BiocManager::install("basilisk")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASILISK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-basilisk"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_basilisk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_basilisk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_basilisk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BasiliskEnvironment", "basilisk", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(BasiliskEnvironment)
    library(basilisk)
    library(jsonlite)

    # --- Local Environment Creation [] ---
    # Key functions: createLocalBasiliskEnv
    tmp_env <- createLocalBasiliskEnv(
        envname="basilisk-vignette-test",
        packages=c("scikit-learn==1.1.1", "numpy==1.22.1")
    )


    # --- Python Execution [] ---
    # Key functions: basiliskRun
    x <- matrix(rnorm(1000), ncol=10)
    results <- basiliskRun(
        env=tmp_env,
        fun=function(mat) {
            module <- reticulate::import("sklearn.decomposition")
            runner <- module\$TruncatedSVD()
            output <- runner\$fit(mat)
            output\$singular_values_
        },
        mat=x
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
        write.csv(as.data.frame(.main), "${prefix}_basilisk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_basilisk_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_basilisk_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BASILISK:", paste0("    basilisk: ", as.character(packageVersion("basilisk")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basilisk_results.csv
    touch ${prefix}_basilisk_output.rds
    echo "BIOC_BASILISK:" > versions.yml
    echo "    basilisk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BASILISK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BASILISK(ch_input)

    emit:
    results  = BIOC_BASILISK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BASILISK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BASILISK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BASILISK.out.versions  // channel: path(versions.yml)
}
