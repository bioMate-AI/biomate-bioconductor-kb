#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiocPkgTools
// Bioconductor has a rich ecosystem of metadata around packages, usage, and build status. This package
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiocPkgTools/inst/doc/BiocPkgTools.R
// Upstream  : biocViews, dplyr, igraph, knitr, visNetwork
// Downstream: none
//
// Install: BiocManager::install("BiocPkgTools")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BIOCPKGTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocpkgtools"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biocpkgtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocpkgtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocpkgtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocPkgTools)
    library(jsonlite)

    # --- bioc Explore [] ---
    # Key functions: biocExplore, toVisNetworkData, visNetwork, visPhysics, visEdges
    biocExplore()
    dep_df = buildPkgDependencyDataFrame()
    g = buildPkgDependencyIgraph(dep_df)
    # --- vis Network [] ---
    # Key functions: visNetwork, visIgraphLayout, visNodes, visPhysics, buildPkgDependencyDataFrame
    library(biocViews)
    data(biocViewsVocab)
    library(igraph)
    # --- orcid_table [] ---
    # Key functions: orcid_table
    orcid_table(oids)
    sessionInfo()

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
        write.csv(as.data.frame(.main), "${prefix}_biocpkgtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_biocpkgtools_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_biocpkgtools_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCPKGTOOLS:", paste0("    biocpkgtools: ", as.character(packageVersion("BiocPkgTools")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocpkgtools_results.csv
    touch ${prefix}_biocpkgtools_output.rds
    echo "BIOC_BIOCPKGTOOLS:" > versions.yml
    echo "    biocpkgtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCPKGTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOCPKGTOOLS(ch_input)

    emit:
    results  = BIOC_BIOCPKGTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCPKGTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCPKGTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCPKGTOOLS.out.versions  // channel: path(versions.yml)
}
