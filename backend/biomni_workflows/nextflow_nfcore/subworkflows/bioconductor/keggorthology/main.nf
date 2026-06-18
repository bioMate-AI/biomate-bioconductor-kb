#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: keggorthology
// graphical representation of the Feb 2010 KEGG Orthology. The KEGG orthology is a set of pathway IDs 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/keggorthology/inst/doc/keggorth.R
// Upstream  : ALL, RBGL, graph
// Downstream: none
//
// Install: BiocManager::install("keggorthology")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_KEGGORTHOLOGY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-keggorthology"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_keggorthology_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_keggorthology_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_keggorthology_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("keggorthology", "jsonlite", "graph", "RBGL", "hgu95av2.db", "ALL")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
    library(keggorthology)
    library(jsonlite)

    # --- Lkkog [] ---
    # Key functions: nodes
    library(keggorthology)
    library(graph)
    data(KOgraph)
    KOgraph
    nodes(KOgraph)[1:5]
    # --- Lkr [] ---
    # Key functions: adj, nodes
    adj(KOgraph, nodes(KOgraph)[1])
    # --- Lkpa [] ---
    # Key functions: between, nodes
    library(RBGL)
    sp.between(KOgraph, nodes(KOgraph)[1], "PPAR signaling pathway")
    # --- Lkta [] ---
    # Key functions: nodeData
    nodeData(KOgraph,,"tag")[1:5]
    # --- Lkde [] ---
    # Key functions: nodeData
    nodeData(KOgraph,,"depth")[1:5]
    # --- Lkd [] ---
    # Key functions: getKOtags
    getKOtags("insulin")
    # --- Lkp [] ---
    # Key functions: getKOprobes
    library(hgu95av2.db)
    mp = getKOprobes("Methionine")
    library(ALL)
    data(ALL)
    ALL[mp,]

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
        write.csv(as.data.frame(.main), "${prefix}_keggorthology_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_keggorthology_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_keggorthology_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_KEGGORTHOLOGY:", paste0("    keggorthology: ", as.character(packageVersion("keggorthology")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_keggorthology_results.csv
    touch ${prefix}_keggorthology_output.rds
    echo "BIOC_KEGGORTHOLOGY:" > versions.yml
    echo "    keggorthology: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KEGGORTHOLOGY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KEGGORTHOLOGY(ch_input)

    emit:
    results  = BIOC_KEGGORTHOLOGY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KEGGORTHOLOGY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KEGGORTHOLOGY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KEGGORTHOLOGY.out.versions  // channel: path(versions.yml)
}
