#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SemDist — evaluate_predictions_ru_mi
// Evaluate predictor performance by calculating remaining uncertainty, misinformation, semantic distance, and other evaluation metrics across thresholds.
// Input: MFO_LABELS_TEST.txt, MFO_PREDS_TEST.txt
// Container: quay.io/biocontainers/bioconductor-semdist:1.44.0--r45hdfd78af_0
// R packages: SemDist
// Bioconductor: 3.20 | R: 4.4
// Requires: SemDist
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load true and predicted annotation files
//  * 2. [Core Analysis] Calculate remaining uncertainty and misinformation at a single threshold
//  * 3. [Core Analysis] Generate a RU-MI curve across multiple thresholds
//  * 4. [Core Analysis] Calculate semantic distance from the RU-MI curve
//  * 5. [Core Analysis] Generate a RU-MI curve with additional precision, recall, and weighted metrics

nextflow.enable.dsl = 2

process BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("SemDist")
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
    
    # Load the SemDist package
    library(SemDist)
    
    # Define input file paths (must exist in the working directory)
    truefile <- "MFO_LABELS_TEST.txt"
    predfile <- "MFO_PREDS_TEST.txt"
    
    # Verify that input files exist before proceeding
    if (!file.exists(truefile)) {
      stop(paste("Required input file missing:", truefile))
    }
    if (!file.exists(predfile)) {
      stop(paste("Required input file missing:", predfile))
    }
    
    # 1. Load true and predicted annotation files
    predictions <- read.table(predfile, colClasses = "character")
    write.csv(predictions, "loaded_predictions.csv", row.names = FALSE)
    
    # 2. Calculate remaining uncertainty and misinformation at a single threshold (0.75)
    rumiTable <- findRUMI("MF", "human", 0.75, truefile, predfile)
    avgRU <- mean(rumiTable\$RU)
    avgMI <- mean(rumiTable\$MI)
    
    # Save single threshold results
    write.csv(rumiTable, "rumi_table_threshold_0.75.csv", row.names = FALSE)
    
    # 3. Generate a RU-MI curve across multiple thresholds (increment of 0.05)
    avgRUMIvals <- RUMIcurve("MF", "human", 0.05, truefile, predfile)
    firstset <- avgRUMIvals[[1]]
    
    # Save the RU-MI curve data
    write.csv(firstset, "rumi_curve_data.csv", row.names = FALSE)
    
    # Plot the RU-MI curve
    pdf("rumi_curve_plot.pdf")
    plot(firstset\$RU, firstset\$MI, 
         xlab = "Remaining Uncertainty (RU)", 
         ylab = "Misinformation (MI)", 
         main = "RU-MI Curve (Step = 0.05)",
         pch = 19, col = "blue")
    lines(firstset\$RU, firstset\$MI, col = "blue")
    dev.off()
    
    # 4. Calculate semantic distance from the RU-MI curve
    semdist <- min(sqrt(firstset\$MI^2 + firstset\$RU^2))
    
    # Save summary metrics
    summary_metrics <- data.frame(
      Metric = c("Average RU (Threshold 0.75)", "Average MI (Threshold 0.75)", "Semantic Distance (Min Euclidean)"),
      Value = c(avgRU, avgMI, semdist)
    )
    write.csv(summary_metrics, "summary_metrics.csv", row.names = FALSE)
    
    # 5. Generate a RU-MI curve with additional precision, recall, and weighted metrics
    rumiout <- RUMIcurve("MF", "human", 0.05, truefile, predfile,
                         add.prec.rec=TRUE, add.weighted=TRUE)
    firstset <- rumiout[[1]]
    
    # Save the extended RU-MI curve data
    write.csv(firstset, "rumi_curve_extended_data.csv", row.names = FALSE)
    
    # Plot the weighted RU-MI curve
    pdf("weighted_rumi_curve_plot.pdf")
    plot(firstset\$WRU, firstset\$WMI, 
         xlab = "Weighted Remaining Uncertainty (WRU)", 
         ylab = "Weighted Misinformation (WMI)", 
         main = "Weighted RU-MI Curve (Step = 0.05)",
         pch = 19, col = "red")
    lines(firstset\$WRU, firstset\$WMI, col = "red")
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI":',
        paste0('    SemDist: ', as.character(packageVersion('SemDist')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_evaluate_predictions_ru_mi.csv versions.yml
    """
}

workflow BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MFO_LABELS_TEST.txt, MFO_PREDS_TEST.txt ] ]

    main:
    BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI(ch_input)

    emit:
    tables   = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI.out.tables
    plots    = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI.out.plots
    objects  = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI.out.objects
    versions = BIOC_SEMDIST_EVALUATE_PREDICTIONS_RU_MI.out.versions
}
