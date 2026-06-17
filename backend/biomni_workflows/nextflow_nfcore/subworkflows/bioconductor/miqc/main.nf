#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miQC — standard_2d_miqc
// Perform quality control filtering on single-cell RNA-seq data by jointly modeling mitochondrial read percentage and the number of detected genes using a 2D mixt
// Input: sce
// Container: quay.io/biocontainers/bioconductor-miqc:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, flexmix, ggplot2, miQC, scater
// Visualizations: plot (ggplot/base)
// QC: per-cell QC metrics, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify mitochondrial genes and calculate per-cell QC metrics using scater::addPerCellQC
//  * 2. [Visualization & Output] Plot QC metrics to visually inspect the dataset using plotMetrics
//  * 3. [Core Analysis] Fit a 2D mixture model (linear, spline, or polynomial) using mixtureModel
//  * 4. [Core Analysis] Inspect model parameters and posterior probabilities using parameters and posterior
//  * 5. [Visualization & Output] Visualize the fitted model and filtering boundary using plotModel and plotFiltering
//  * 6. [Core Analysis] Filter out compromised cells from the SingleCellExperiment object using filterCells

nextflow.enable.dsl = 2

process BIOC_MIQC_STANDARD_2D_MIQC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("scater", "miQC", "flexmix", "ggplot2")
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
        
        # Load required libraries
        suppressPackageStartupMessages({
            library(scater)
            library(miQC)
            library(flexmix)
            library(splines)
            library(ggplot2)
        })
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input
        # -----------------------------------------------------------------------------
        if (file.exists("sce")) {
            sce <- readRDS("sce")
        } else if (file.exists("sce.rds")) {
            sce <- readRDS("sce.rds")
        } else {
            stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
        }
        
        # -----------------------------------------------------------------------------
        # 2. Identify Mitochondrial Genes and Calculate Per-Cell QC Metrics
        # -----------------------------------------------------------------------------
        mt_genes <- grepl("^mt-",  rownames(sce), ignore.case = TRUE)
        # If no genes start with mt- (e.g. human MT-), try MT-
        if (sum(mt_genes) == 0) {
            mt_genes <- grepl("^MT-", rownames(sce))
        }
        
        feature_ctrls <- list(mito = rownames(sce)[mt_genes])
        sce <- addPerCellQC(sce, subsets = feature_ctrls)
        
        # -----------------------------------------------------------------------------
        # 3. Plot QC Metrics
        # -----------------------------------------------------------------------------
        pdf("qc_metrics_plot.pdf", width = 7, height = 6)
        p_metrics <- plotMetrics(sce)
        print(p_metrics)
        dev.off()
        
        # -----------------------------------------------------------------------------
        # 4. Fit 2D Mixture Model (Linear)
        # -----------------------------------------------------------------------------
        model <- mixtureModel(sce)
        
        # Save model parameters
        params <- parameters(model)
        write.csv(as.data.frame(params), "model_linear_parameters.csv", row.names = TRUE)
        
        # Save posterior probabilities
        post_prob <- posterior(model)
        write.csv(as.data.frame(post_prob), "model_linear_posterior.csv", row.names = FALSE)
        
        # -----------------------------------------------------------------------------
        # 5. Visualize Fitted Model and Filtering Boundary
        # -----------------------------------------------------------------------------
        pdf("model_linear_plot.pdf", width = 7, height = 6)
        p_model <- plotModel(sce, model)
        print(p_model)
        dev.off()
        
        pdf("filtering_linear_plot.pdf", width = 7, height = 6)
        p_filter <- plotFiltering(sce, model)
        print(p_filter)
        dev.off()
        
        # -----------------------------------------------------------------------------
        # 6. Filter Cells
        # -----------------------------------------------------------------------------
        sce_filtered <- filterCells(sce, model)
        saveRDS(sce_filtered, "filtered_sce.rds")
        
        # -----------------------------------------------------------------------------
        # 7. Alternative Non-linear Models (Spline & Polynomial)
        # -----------------------------------------------------------------------------
        # Wrap in tryCatch to ensure pipeline robustness if user data is not compatible
        tryCatch({
            model2 <- mixtureModel(sce, model_type = "spline")
            
            pdf("model_spline_plot.pdf", width = 7, height = 6)
            print(plotModel(sce, model2))
            dev.off()
            
            pdf("filtering_spline_plot.pdf", width = 7, height = 6)
            print(plotFiltering(sce, model2))
            dev.off()
        }, error = function(e) {
            warning("Spline mixture model fitting failed: ", e\$message)
        })
        
        tryCatch({
            model3 <- mixtureModel(sce, model_type = "polynomial")
            
            pdf("model_polynomial_plot.pdf", width = 7, height = 6)
            print(plotModel(sce, model3))
            dev.off()
            
            pdf("filtering_polynomial_plot.pdf", width = 7, height = 6)
            print(plotFiltering(sce, model3))
            dev.off()
        }, error = function(e) {
            warning("Polynomial mixture model fitting failed: ", e\$message)
        })
        
        # -----------------------------------------------------------------------------
        # 8. Adjusting Filtering Parameters (e.g., for Cancer Datasets)
        # -----------------------------------------------------------------------------
        tryCatch({
            pdf("filtering_adjusted_plot.pdf", width = 7, height = 6)
            p_adj <- plotFiltering(sce, model, posterior_cutoff = 0.6, 
                                   enforce_left_cutoff = TRUE, 
                                   keep_all_below_boundary = TRUE)
            print(p_adj)
            dev.off()
        }, error = function(e) {
            warning("Adjusted filtering plot generation failed: ", e\$message)
        })
        
        message("miQC pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MIQC_STANDARD_2D_MIQC":',
        paste0('    miQC: ', as.character(packageVersion('miQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_2d_miqc.csv versions.yml
    """
}

workflow BIOC_MIQC_STANDARD_2D_MIQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_MIQC_STANDARD_2D_MIQC(ch_input)

    emit:
    tables   = BIOC_MIQC_STANDARD_2D_MIQC.out.tables
    plots    = BIOC_MIQC_STANDARD_2D_MIQC.out.plots
    objects  = BIOC_MIQC_STANDARD_2D_MIQC.out.objects
    versions = BIOC_MIQC_STANDARD_2D_MIQC.out.versions
}
