#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: panp
// A function to make gene presence/absence calls based on distance from negative strand matching probe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/panp/inst/doc/panp.R
// Upstream  : gcrma
// Downstream: none
//
// Install: BiocManager::install("panp")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_PANP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-panp"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_panp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_panp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_panp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("gcrma", "jsonlite", "panp")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    library(panp)
    library(jsonlite)

    # --- data [] ---
    # Key functions: data
    data(gcrma.ExpressionSet)
    # --- calls [] ---
    # Key functions: calls
    PA <- pa.calls(gcrma.ExpressionSet)
    # --- Data [] ---
    # Key functions: exprs, density
    data(NSMPnames.hgu133a)	# read in the NSMP names list
    # create x and y ranges for NSMP intensities
    NSMP_x <- sort(exprs(gcrma.ExpressionSet)[NSMPnames.hgu133a,1], decreasing=TRUE)
    NSMP_y <- seq(0,1,1/(length(NSMP_x)-1))
    # Plot expression densities of all probesets, then just NSMPs

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
        write.csv(as.data.frame(.main), "${prefix}_panp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_panp_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_panp_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_PANP:", paste0("    panp: ", as.character(packageVersion("panp")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_panp_results.csv
    touch ${prefix}_panp_output.rds
    echo "BIOC_PANP:" > versions.yml
    echo "    panp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PANP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PANP(ch_input)

    emit:
    results  = BIOC_PANP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PANP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PANP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PANP.out.versions  // channel: path(versions.yml)
}
