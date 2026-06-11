#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnVILAz
// The AnVIL is a cloud computing resource developed in part by the National Human Genome Research Inst
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnVILAz/inst/doc/AnVILAzWorkspaces.R
// Upstream  : dplyr
// Downstream: none
//
// Install: BiocManager::install("AnVILAz")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ANVILAZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anvilaz"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anvilaz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anvilaz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anvilaz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnVILAz)
    library(jsonlite)

    # --- Workspace Selection [] ---
    # Key functions: avworkspace
    AnVILAz::avworkspace("my-azure-namespace/my-azure-workspace")
    current_ws <- AnVILAz::avworkspace()


    # --- Resource Retrieval [] ---
    # Key functions: avworkspaces
    ws_list <- AnVILAz::avworkspaces()
    azure_workspaces <- ws_list[ws_list\$platform == "Azure", ]

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
        write.csv(as.data.frame(.main), "${prefix}_anvilaz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_anvilaz_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_anvilaz_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANVILAZ:", paste0("    anvilaz: ", as.character(packageVersion("AnVILAz")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anvilaz_results.csv
    touch ${prefix}_anvilaz_output.rds
    echo "BIOC_ANVILAZ:" > versions.yml
    echo "    anvilaz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANVILAZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANVILAZ(ch_input)

    emit:
    results  = BIOC_ANVILAZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANVILAZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANVILAZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANVILAZ.out.versions  // channel: path(versions.yml)
}
