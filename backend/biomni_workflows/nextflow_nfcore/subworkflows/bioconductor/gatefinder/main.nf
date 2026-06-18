#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GateFinder — gate_finder_optimization
// Identify and visualize an optimal sequence of 2D polygon gates to isolate a target cell population from high-dimensional cytometry data.
// Input: rawdata, targetpop
// Container: quay.io/biocontainers/bioconductor-gatefinder:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GateFinder, flowCore
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the target cell population based on marker expression thresholding
//  * 2. [Core Analysis] Subset the expression matrix to markers of interest
//  * 3. [Core Analysis] Run GateFinder to optimize the gating strategy
//  * 4. [Visualization & Output] Plot the sequential 2D gating steps
//  * 5. [Visualization & Output] Plot the F-measure, purity, and yield metrics across gating steps
//  * 6. [Core Analysis] Refine the gating strategy by adjusting outlier.percentile or beta parameters

nextflow.enable.dsl = 2

process BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("GateFinder", "flowCore")
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
    
    library(GateFinder)
    library(flowCore)
    
    # Helper function to safely save results summary to CSV
    save_results_csv <- function(res, filename) {
      tryCatch({
        # Try S4 slots first
        df <- data.frame(
          Step = seq_along(res@f.measure),
          F_measure = res@f.measure,
          Precision = res@precision,
          Recall = res@recall
        )
        write.csv(df, filename, row.names = FALSE)
      }, error = function(e) {
        tryCatch({
          # Try list-like access
          df <- data.frame(
            Step = seq_along(res\$f.measure),
            F_measure = res\$f.measure,
            Precision = res\$precision,
            Recall = res\$recall
          )
          write.csv(df, filename, row.names = FALSE)
        }, error = function(e2) {
          message("Could not save CSV: ", e2\$message)
        })
      })
    }
    
    # 1. Read User Inputs from the working directory
    if (file.exists("rawdata.rds")) {
      rawdata <- readRDS("rawdata.rds")
    } else if (file.exists("rawdata.fcs")) {
      rawdata <- read.FCS("rawdata.fcs", transformation = FALSE)
    } else {
      stop("Error: rawdata file (rawdata.rds or rawdata.fcs) not found in the working directory.")
    }
    
    if (file.exists("targetpop.rds")) {
      targetpop <- readRDS("targetpop.rds")
    } else if (file.exists("targetpop.csv")) {
      targetpop <- as.logical(read.csv("targetpop.csv")[, 1])
    } else {
      stop("Error: targetpop file (targetpop.rds or targetpop.csv) not found in the working directory.")
    }
    
    # Set up marker names and indices dynamically based on the input rawdata
    marker.names <- colnames(rawdata)
    if (is.null(marker.names)) {
      marker.names <- paste0("Marker_", seq_len(ncol(rawdata)))
      colnames(rawdata) <- marker.names
    }
    prop.markers <- seq_along(marker.names)
    
    # Open PDF device to capture all diagnostic and optimization plots
    pdf("gate_finder_plots.pdf", width = 11, height = 8.5)
    
    # 2. Define and visualize the target cell population based on marker expression thresholding
    tryCatch({
      # Attempt the exact vignette plot using columns 2 and 34
      plot(exprs(rawdata)[ , c(2,34)], pch='.', col=targetpop+1, 
           xlab='Cell Length', ylab='p-p38')
      abline(h=3.5, col=3, lwd=2, lty=2)
    }, error = function(e) {
      message("Could not plot columns 2 and 34. Plotting first two available columns instead.")
      cols_to_plot <- seq_len(min(2, ncol(rawdata)))
      if (length(cols_to_plot) == 2) {
        plot(exprs(rawdata)[ , cols_to_plot], pch='.', col=targetpop+1,
             xlab=colnames(rawdata)[cols_to_plot[1]], ylab=colnames(rawdata)[cols_to_plot[2]])
      }
    })
    
    # 3. Subset the expression matrix to markers of interest
    x=exprs(rawdata)[ , prop.markers]
    colnames(x)=marker.names[prop.markers]
    
    # 4. Run GateFinder to optimize the gating strategy (Default Run)
    results=GateFinder(x, targetpop)
    saveRDS(results, "gate_finder_results_default.rds")
    save_results_csv(results, "gate_finder_metrics_default.csv")
    
    # 5. Plot the sequential 2D gating steps and metrics
    plot (x, results, c(2,3), targetpop)
    plot(results)
    
    # 6. Refine the gating strategy by adjusting outlier.percentile
    results=GateFinder(x, targetpop, outlier.percentile=0.5)     
    saveRDS(results, "gate_finder_results_outlier_0.5.rds")
    save_results_csv(results, "gate_finder_metrics_outlier_0.5.csv")
    plot (x, results, c(2,3), targetpop)
    plot(results)
    
    # 7. Refine the gating strategy by adjusting beta parameter
    results=GateFinder(x, targetpop, beta=0.5)     
    saveRDS(results, "gate_finder_results_beta_0.5.rds")
    save_results_csv(results, "gate_finder_metrics_beta_0.5.csv")
    plot (x, results, c(2,3), targetpop)
    plot(results)
    
    # Close the graphics device
    dev.off()
    
    message("GateFinder pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION":',
        paste0('    GateFinder: ', as.character(packageVersion('GateFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gate_finder_optimization.csv versions.yml
    """
}

workflow BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rawdata, targetpop ] ]

    main:
    BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION.out.tables
    plots    = BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION.out.plots
    objects  = BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION.out.objects
    versions = BIOC_GATEFINDER_GATE_FINDER_OPTIMIZATION.out.versions
}
