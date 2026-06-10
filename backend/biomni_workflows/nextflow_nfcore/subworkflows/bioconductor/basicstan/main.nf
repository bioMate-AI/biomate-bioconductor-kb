#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BASiCStan — basics_stan_inference
// Perform parameter estimation for single-cell RNA-seq data using Stan-based inference and convert the output for downstream BASiCS analysis.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-basicstan:1.12.0--r45ha27e39d_0
// R packages: SingleCellExperiment, BASiCStan
// Bioconductor: 3.20 | R: 4.4
// Requires: BASiCStan, SingleCellExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and generate or load the SingleCellExperiment dataset
//  * 2. [Core Analysis] Run parameter estimation using BASiCStan to obtain a BASiCS_Chain object
//  * 3. [Core Analysis] Run BASiCStan with ReturnBASiCS = FALSE to obtain a raw Stan object for diagnostics
//  * 4. [Core Analysis] Convert the raw Stan object to a BASiCS_Chain object using Stan2BASiCS

nextflow.enable.dsl = 2

process BIOC_BASICSTAN_BASICS_STAN_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "BASiCStan")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    suppressPackageStartupMessages({
      library("BASiCStan")
      library("SingleCellExperiment")
    })
    
    set.seed(42)
    
    # Read input SingleCellExperiment object from the working directory
    if (file.exists("sce")) {
      sce <- readRDS("sce")
    } else if (file.exists("sce.rds")) {
      sce <- readRDS("sce.rds")
    } else {
      stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    # 1. Run parameter estimation using BASiCStan to obtain a BASiCS_Chain object
    stan_fit <- BASiCStan(sce, Method = "sampling")
    saveRDS(stan_fit, "stan_fit.rds")
    
    # 2. Generate and save the fit plot
    pdf("basics_fit_plot.pdf", width = 7, height = 7)
    tryCatch({
      BASiCS_ShowFit(stan_fit)
    }, error = function(e) {
      warning("BASiCS_ShowFit failed: ", e\$message)
    })
    dev.off()
    
    # 3. Run BASiCStan with ReturnBASiCS = FALSE to obtain a raw Stan object for diagnostics
    stan_obj <- BASiCStan(sce, ReturnBASiCS = FALSE, Method = "sampling")
    saveRDS(stan_obj, "stan_obj.rds")
    
    # 4. Extract and save summary diagnostics
    stan_summary_df <- summary(stan_obj)\$summary
    write.csv(stan_summary_df, "stan_summary.csv", row.names = TRUE)
    print(head(stan_summary_df))
    
    # 5. Convert the raw Stan object to a BASiCS_Chain object using Stan2BASiCS
    converted_chain <- Stan2BASiCS(stan_obj)
    saveRDS(converted_chain, "converted_chain.rds")

    writeLines(c(
        '"BIOC_BASICSTAN_BASICS_STAN_INFERENCE":',
        paste0('    BASiCStan: ', as.character(packageVersion('BASiCStan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basics_stan_inference.csv versions.yml
    """
}

workflow BIOC_BASICSTAN_BASICS_STAN_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_BASICSTAN_BASICS_STAN_INFERENCE(ch_input)

    emit:
    tables   = BIOC_BASICSTAN_BASICS_STAN_INFERENCE.out.tables
    plots    = BIOC_BASICSTAN_BASICS_STAN_INFERENCE.out.plots
    objects  = BIOC_BASICSTAN_BASICS_STAN_INFERENCE.out.objects
    versions = BIOC_BASICSTAN_BASICS_STAN_INFERENCE.out.versions
}
