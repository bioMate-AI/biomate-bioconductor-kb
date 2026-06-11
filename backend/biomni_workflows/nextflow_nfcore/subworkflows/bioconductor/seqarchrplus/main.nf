#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqArchRplus
// seqArchRplus facilitates downstream analyses of promoter sequence architectures/clusters identified 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqArchRplus/inst/doc/seqArchRplus.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seqArchRplus")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SEQARCHRPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqarchrplus"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqarchrplus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqarchrplus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqarchrplus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("seqArchRplus", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(seqArchRplus)
    library(jsonlite)

    # --- Initial Cluster Curation [] ---
    # Key functions: curate_clusters
    seqArchR_curated_clusts <- curate_clusters(
        sname = "RAL28_10_to_12h",
        use_aggl = "complete",
        use_dist = "euclid",
        seqArchR_result = seqArchR_result,
        iter = 5,
        pos_lab = NULL,
        regularize = TRUE,
        topn = 50,
        use_cutk = 2,
        final = FALSE,
        dir_path = NULL
    )

    # --- Cluster Reassignment and Refinement [] ---
    # Key functions: curate_clusters
    seqArchR_curated_clusts <- curate_clusters(
        sname = "RAL28_10_to_12h",
        use_aggl = "complete",
        use_dist = "euclid",
        seqArchR_result = seqArchR_result,
        iter = 5,
        regularize = TRUE,
        topn = 50,
        use_cutk = 5,
        need_change = list(c(2)),
        change_to = list(c(1)),
        final = FALSE,
        dir_path = NULL
    )

    # --- Final Cluster Curation [] ---
    # Key functions: curate_clusters
    seqArchR_curated_clusts <- curate_clusters(
        sname = "RAL28_10_to_12h",
        use_aggl = "complete",
        use_dist = "euclid",
        seqArchR_result = seqArchR_result,
        iter = 5,
        pos_lab = NULL,
        regularize = FALSE,
        topn = 50,
        use_cutk = 5,
        need_change = list(c(2)),
        change_to = list(c(1)),
        final = TRUE,
        dir_path = NULL
    )

    # --- Sequence Logo Generation [] ---
    # Key functions: per_cluster_seqlogos
    seqlogos_oneplot_pl <- per_cluster_seqlogos(
        sname = "RAL28_10_to_12h",
        seqs = raw_seqs,
        clusts = unord_clusts,
        pos_lab = -45:45,
        bits_yax = "auto",
        strand_sep = FALSE,
        one_plot = TRUE,
        txt_size = 12,
        dir_path = NULL
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
        write.csv(as.data.frame(.main), "${prefix}_seqarchrplus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_seqarchrplus_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_seqarchrplus_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQARCHRPLUS:", paste0("    seqarchrplus: ", as.character(packageVersion("seqArchRplus")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqarchrplus_results.csv
    touch ${prefix}_seqarchrplus_output.rds
    echo "BIOC_SEQARCHRPLUS:" > versions.yml
    echo "    seqarchrplus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQARCHRPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQARCHRPLUS(ch_input)

    emit:
    results  = BIOC_SEQARCHRPLUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQARCHRPLUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQARCHRPLUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQARCHRPLUS.out.versions  // channel: path(versions.yml)
}
