#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OrganismDbi
// The package enables a simple unified interface to several annotation packages each of which has its 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OrganismDbi/inst/doc/OrganismDbi.R
// Upstream  : none
// Downstream: Homo.sapiens, Mus.musculus, Rattus.norvegicus
//
// Install: BiocManager::install("OrganismDbi")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ORGANISMDBI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-organismdbi"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_organismdbi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_organismdbi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_organismdbi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OrganismDbi)
    library(jsonlite)


    # --- Figure [] ---
    # Key functions: include_graphics
    knitr::include_graphics("relationships-between-annotation-packages.png")

    # --- Columns [] ---
    # Key functions: columns
    library(Homo.sapiens)
    columns(Homo.sapiens)

    # --- Keys1 [] ---
    # Key functions: keytypes
    keytypes(Homo.sapiens)

    # --- Keys2 [] ---
    # Key functions: keys
    head(keys(Homo.sapiens, keytype = "ENTREZID"))

    # --- Select [] ---
    # Key functions: keys, select
    k <- head(keys(Homo.sapiens, keytype = "ENTREZID"), n = 3)
    select(
      Homo.sapiens,
      keys = k,
      columns = c("TXNAME", "SYMBOL"),
      keytype = "ENTREZID"
    )

    # --- Transcripts [] ---
    # Key functions: transcripts
    transcripts(Homo.sapiens, columns = c("TXNAME", "SYMBOL"))

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
        write.csv(as.data.frame(.main), "${prefix}_organismdbi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_organismdbi_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_organismdbi_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ORGANISMDBI:", paste0("    organismdbi: ", as.character(packageVersion("OrganismDbi")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_organismdbi_results.csv
    touch ${prefix}_organismdbi_output.rds
    echo "BIOC_ORGANISMDBI:" > versions.yml
    echo "    organismdbi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ORGANISMDBI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ORGANISMDBI(ch_input)

    emit:
    results  = BIOC_ORGANISMDBI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ORGANISMDBI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ORGANISMDBI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ORGANISMDBI.out.versions  // channel: path(versions.yml)
}
