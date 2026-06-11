#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ssrch
// Demonstrate tokenization and a search gadget for collections of CSV files.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ssrch/inst/doc/ssrch.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ssrch")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SSRCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ssrch"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ssrch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ssrch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ssrch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ssrch)
    library(jsonlite)

    # --- retrieve_doc [] ---
    # Key functions: retrieve_doc
    retrieve_doc("ERP010142", docset_cancer68)[1:3,1:5]
    # --- search Docs [] ---
    # Key functions: searchDocs
    library(ssrch)
    searchDocs("Adjacent", docset_cancer68, ignore.case=TRUE)
    # --- get Class [] ---
    # Key functions: getClass
    getClass(class(docset_cancer68))
    # --- datatable [] ---
    # Key functions: datatable
    NSCdocs = lapply(unique(NSChits\$docs),
    function(x) retrieve_doc(x, docset_cancer68))
    names(NSCdocs) = NSChits\$docs

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
        write.csv(as.data.frame(.main), "${prefix}_ssrch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_ssrch_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_ssrch_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SSRCH:", paste0("    ssrch: ", as.character(packageVersion("ssrch")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ssrch_results.csv
    touch ${prefix}_ssrch_output.rds
    echo "BIOC_SSRCH:" > versions.yml
    echo "    ssrch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SSRCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SSRCH(ch_input)

    emit:
    results  = BIOC_SSRCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SSRCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SSRCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SSRCH.out.versions  // channel: path(versions.yml)
}
