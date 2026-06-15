#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CytoML
// Uses platform-specific implemenations of the GatingML2.0 standard to exchange gated cytometry data w
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CytoML/inst/doc/HowToExportGatingSet.R
// Upstream  : flowWorkspace, ggcyto, ncdfFlow, openCyto
// Downstream: none
//
// Install: BiocManager::install("CytoML")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOML {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytoml"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_cytoml_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytoml_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytoml_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("CytoML", "jsonlite", "openCyto")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(CytoML)
    library(jsonlite)


    # --- Warning=false [] ---
    # Key functions: fread, tempfile, gatingTemplate, gating, toggle.helperGates, openCyto
    library(openCyto)
    #load the original template for tcell panel
    tbl <- data.table::fread(system.file("extdata/gating_template/tcell.csv", package = "openCyto"))
    #modify some paramters to fit the current data range
    tbl[5, gating_args:= "gate_range = c(1e3, 3e3)"]
    tbl[c(8,11), gating_args:= "gate_range = c(2e3, 3e3)"]
    #write the new template to disc
    gtFile <- tempfile()
    write.csv(tbl, file = gtFile)
    ##reload the new template
    gt <- gatingTemplate(gtFile)
    #run the gating
    gating(gt, gs)
    #hide the gates that are not of interest
    toggle.helperGates(gt, gs)

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
        write.csv(as.data.frame(.main), "${prefix}_cytoml_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_cytoml_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_cytoml_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOML:", paste0("    cytoml: ", as.character(packageVersion("CytoML")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytoml_results.csv
    touch ${prefix}_cytoml_output.rds
    echo "BIOC_CYTOML:" > versions.yml
    echo "    cytoml: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_CYTOML(ch_input)

    emit:
    results  = BIOC_CYTOML.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOML.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOML.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOML.out.versions  // channel: path(versions.yml)
}
