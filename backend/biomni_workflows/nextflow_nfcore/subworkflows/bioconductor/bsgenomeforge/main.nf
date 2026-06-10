#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BSgenomeForge
// A set of tools to forge BSgenome data packages. Supersedes the old seed-based tools from the BSgenom
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BSgenomeForge/inst/doc/AdvancedBSgenomeForge.R
// Upstream  : BSgenome
// Downstream: none
//
// Install: BiocManager::install("BSgenomeForge")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_BSGENOMEFORGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bsgenomeforge"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bsgenomeforge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bsgenomeforge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bsgenomeforge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BSgenomeForge)
    library(jsonlite)

    # --- Forgebsgenomedatapkg [] ---
    # Key functions: forgeBSgenomeDataPkg
    ## library(BSgenomeForge)
    ## forgeBSgenomeDataPkg("path/to/my/seed")
    # --- Forgemaskedbsgenomedatapkg [] ---
    # Key functions: forgeMaskedBSgenomeDataPkg
    ## library(BSgenomeForge)
    ## forgeMaskedBSgenomeDataPkg("path/to/my/seed")

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
        write.csv(as.data.frame(.main), "${prefix}_bsgenomeforge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_bsgenomeforge_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_bsgenomeforge_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_BSGENOMEFORGE:", paste0("    bsgenomeforge: ", as.character(packageVersion("BSgenomeForge")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsgenomeforge_results.csv
    touch ${prefix}_bsgenomeforge_output.rds
    echo "BIOC_BSGENOMEFORGE:" > versions.yml
    echo "    bsgenomeforge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BSGENOMEFORGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BSGENOMEFORGE(ch_input)

    emit:
    results  = BIOC_BSGENOMEFORGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BSGENOMEFORGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BSGENOMEFORGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BSGENOMEFORGE.out.versions  // channel: path(versions.yml)
}
