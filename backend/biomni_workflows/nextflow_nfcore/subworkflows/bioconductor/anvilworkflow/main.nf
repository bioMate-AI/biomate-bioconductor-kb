#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnVILWorkflow
// The AnVIL is a cloud computing resource developed in part by the National Human Genome Research Inst
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnVILWorkflow/inst/doc/salmon.R
// Upstream  : AnVIL, AnVILGCP, BiocManager
// Downstream: none
//
// Install: BiocManager::install("AnVILWorkflow")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_ANVILWORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anvilworkflow"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anvilworkflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anvilworkflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anvilworkflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("AnVILWorkflow", "Terra", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(AnVILWorkflow)
    library(Terra)
    library(jsonlite)

    # --- Input Configuration [] ---
    # Key functions: inputs
    wf_inputs <- anvilworkflow::inputs(wf)
    wf_inputs\$input_file <- "gs://my-bucket/data.fastq"
    anvilworkflow::inputs(wf) <- wf_inputs


    # --- Workflow Submission [] ---
    # Key functions: submit, jobs
    job <- anvilworkflow::submit(wf)
    status <- anvilworkflow::jobs(wf)

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
        write.csv(as.data.frame(.main), "${prefix}_anvilworkflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_anvilworkflow_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_anvilworkflow_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANVILWORKFLOW:", paste0("    anvilworkflow: ", as.character(packageVersion("AnVILWorkflow")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anvilworkflow_results.csv
    touch ${prefix}_anvilworkflow_output.rds
    echo "BIOC_ANVILWORKFLOW:" > versions.yml
    echo "    anvilworkflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANVILWORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANVILWORKFLOW(ch_input)

    emit:
    results  = BIOC_ANVILWORKFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANVILWORKFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANVILWORKFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANVILWORKFLOW.out.versions  // channel: path(versions.yml)
}
