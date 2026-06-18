#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SIM
// Finds associations between two human genomic datasets.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SIM/inst/doc/SIM.R
// Upstream  : RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("SIM")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_SIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sim"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("jsonlite", "RColorBrewer", "SIM")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    library(SIM)
    library(jsonlite)

    # --- Data Assembly [] ---
    # Key functions: assemble.data
    assembled_data <- assemble.data(
        dep.data = expression_matrix,
        indep.data = copynumber_matrix,
        dep.ann = expression_annotation,
        indep.ann = copynumber_annotation,
        dep.id = "probeset",
        dep.chr = "chr",
        dep.pos = "pos",
        indep.id = "clone",
        indep.chr = "chr",
        indep.pos = "pos"
    )

    # --- Integrated Association Analysis [] ---
    # Key functions: integrated.analysis
    analysis_results <- integrated.analysis(
        data = assembled_data,
        method = "pearson",
        alternative = "greater",
        p.adjust.method = "BY",
        run.subset = TRUE,
        subset.chr = c(1, 2)
    )

    # --- Tabulate Results [] ---
    # Key functions: tabulate.pvals, tabulate.top.dep
    pvals_table <- tabulate.pvals(
        sim.list = analysis_results,
        p.cut = 0.05,
        adjust = TRUE
    )
    top_dep_table <- tabulate.top.dep(
        sim.list = analysis_results,
        p.cut = 0.05,
        adjust = TRUE
    )

    # --- Visualization [] ---
    # Key functions: sim.plot.zscore.heatmap, sim.plot.pvals.on.genome
    sim.plot.zscore.heatmap(
        sim.list = analysis_results,
        adjust = TRUE,
        p.cut = 0.05,
        pdf = FALSE
    )
    sim.plot.pvals.on.genome(
        sim.list = analysis_results,
        adjust = TRUE,
        p.cut = 0.05,
        pdf = FALSE
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
        write.csv(as.data.frame(.main), "${prefix}_sim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_sim_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_sim_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIM:", paste0("    sim: ", as.character(packageVersion("SIM")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sim_results.csv
    touch ${prefix}_sim_output.rds
    echo "BIOC_SIM:" > versions.yml
    echo "    sim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIM(ch_input)

    emit:
    results  = BIOC_SIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIM.out.versions  // channel: path(versions.yml)
}
