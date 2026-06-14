#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnaseqcomp — benchmark_quantification_pipelines
// Compare and benchmark multiple RNA-seq quantification pipelines on specificity and sensitivity metrics using a two-condition dataset.
// Input: simdata$quant, simdata$samp, simdata$meta
// Container: quay.io/biocontainers/bioconductor-rnaseqcomp:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: rnaseqcomp
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Prepare Factors and Logical Vectors
//  * 3. [Visualization & Output] Calibrate Quantification Signals
//  * 4. [Visualization & Output] Evaluate and Plot Specificity & Sensitivity
//  * 5. [Visualization & Output] Export Numerical Metrics to CSV

nextflow.enable.dsl = 2

process BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES {
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
    .bm_deps <- c("rnaseqcomp")
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
    
    # Load required library
    library(rnaseqcomp)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    
    simdata <- list()
    
    # Read quantification list
    if (file.exists("simdata_quant.rds")) {
      simdata\$quant <- readRDS("simdata_quant.rds")
    } else {
      stop("Error: Required input file 'simdata_quant.rds' not found in the working directory.")
    }
    
    # Read sample metadata
    if (file.exists("simdata_samp.rds")) {
      simdata\$samp <- readRDS("simdata_samp.rds")
    } else if (file.exists("simdata_samp.csv")) {
      simdata\$samp <- read.csv("simdata_samp.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: Required input file 'simdata_samp.rds' or 'simdata_samp.csv' not found.")
    }
    
    # Read feature metadata
    if (file.exists("simdata_meta.rds")) {
      simdata\$meta <- readRDS("simdata_meta.rds")
    } else if (file.exists("simdata_meta.csv")) {
      simdata\$meta <- read.csv("simdata_meta.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: Required input file 'simdata_meta.rds' or 'simdata_meta.csv' not found.")
    }
    
    # ==========================================
    # --- Prepare Factors and Logical Vectors ---
    # ==========================================
    
    condInfo <- factor(simdata\$samp\$condition)
    repInfo <- factor(simdata\$samp\$replicate)
    evaluationFeature <- rep(TRUE, nrow(simdata\$meta))
    calibrationFeature <- simdata\$meta\$house & simdata\$meta\$chr == 'chr1'
    unitReference <- 1
    
    # ==========================================
    # --- Calibrate Quantification Signals ---
    # ==========================================
    
    dat <- signalCalibrate(simdata\$quant, condInfo, repInfo, evaluationFeature,
         calibrationFeature, unitReference, 
         calibrationFeature2 = calibrationFeature)
    
    # Save calibrated S4 object
    saveRDS(dat, "calibrated_data.rds")
    
    # ==========================================
    # --- Evaluate and Plot Specificity & Sensitivity ---
    # ==========================================
    
    # Open PDF device to save all benchmark plots
    pdf("rnaseqcomp_benchmark_plots.pdf", width = 8, height = 10)
    par(mfrow = c(3, 2))
    
    # 4.1 Specificity on expressed features
    sd_metrics <- plotSD(dat, ylim = c(0, 1.4))
    
    # 4.2 Specificity on non-expressed features
    ne_metrics <- plotNE(dat, xlim = c(0.5, 1))
    
    # 4.3 Specificity for genes with only two annotated transcripts
    tx2_metrics <- plot2TX(dat, genes = simdata\$meta\$gene, ylim = c(0, 0.6))
    
    # 4.4 Sensitivity in differential analysis (ROC)
    roc_metrics <- plotROC(dat, simdata\$meta\$positive, simdata\$meta\$fcsign, ylim = c(0, 0.8))
    
    # 4.5 Sensitivity via estimated fold change distributions (filtering out "off.on" transcripts)
    simdata\$meta\$fcsign[simdata\$meta\$fcstatus == "off.on"] <- NA
    fc_metrics <- plotFC(dat, simdata\$meta\$positive, simdata\$meta\$fcsign, ylim = c(0, 1.2))
    
    # Close PDF device
    dev.off()
    
    # ==========================================
    # --- Export Numerical Metrics to CSV ---
    # ==========================================
    
    if (!is.null(sd_metrics)) {
      write.csv(sd_metrics\$med, "sd_median_metrics.csv", row.names = TRUE)
      write.csv(sd_metrics\$se, "sd_se_metrics.csv", row.names = TRUE)
    }
    
    if (!is.null(ne_metrics)) {
      write.csv(ne_metrics\$NE, "ne_proportions.csv", row.names = TRUE)
      write.csv(ne_metrics\$NN, "nn_proportions.csv", row.names = TRUE)
    }
    
    if (!is.null(tx2_metrics)) {
      write.csv(tx2_metrics\$mean, "tx2_mean_metrics.csv", row.names = TRUE)
      write.csv(tx2_metrics\$se, "tx2_se_metrics.csv", row.names = TRUE)
    }
    
    if (!is.null(roc_metrics)) {
      write.csv(as.data.frame(t(roc_metrics)), "roc_pauc_metrics.csv", row.names = TRUE)
    }
    
    if (!is.null(fc_metrics)) {
      write.csv(fc_metrics\$med, "fc_median_metrics.csv", row.names = TRUE)
      write.csv(fc_metrics\$se, "fc_se_metrics.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES":',
        paste0('    rnaseqcomp: ', as.character(packageVersion('rnaseqcomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_benchmark_quantification_pipelines.csv versions.yml
    """
}

workflow BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simdata$quant, simdata$samp, simdata$meta ] ]

    main:
    BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES(ch_input)

    emit:
    tables   = BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES.out.tables
    plots    = BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES.out.plots
    objects  = BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES.out.objects
    versions = BIOC_RNASEQCOMP_BENCHMARK_QUANTIFICATION_PIPELINES.out.versions
}
