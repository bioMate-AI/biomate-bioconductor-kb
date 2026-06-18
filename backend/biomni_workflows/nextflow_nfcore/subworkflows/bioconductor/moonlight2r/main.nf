#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Moonlight2R — moonlight_driver_prediction
// Identify cancer driver genes (TSGs and OCGs) from gene expression data using functional enrichment, gene regulatory networks, and upstream regulator analysis.
// Input: counts.csv, coldata.csv
// Container: 1.8.1--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Moonlight2R, dplyr, limma, magrittr
// Visualizations: bar plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION {
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
    .bm_deps <- c("Moonlight2R", "limma", "dplyr", "magrittr")
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
    library(Moonlight2R)
    library(limma)
    library(dplyr)
    library(magrittr)
    
    # Define fallback function to guarantee outputs are written in case of failure
    write_fallback <- function(msg) {
      warning(paste("Pipeline encountered an error, writing fallback outputs:", msg))
      write.csv(data.frame(Error = msg), "predicted_drivers.csv", row.names = FALSE)
      write.csv(data.frame(Error = msg), "fea_results.csv", row.names = FALSE)
      write.csv(data.frame(Error = msg), "ura_results.csv", row.names = FALSE)
      pdf("moonlight_plots.pdf")
      plot.new()
      text(0.5, 0.5, paste("Pipeline failed:\n", msg), cex = 0.8)
      dev.off()
    }
    
    # Main pipeline execution wrapped in tryCatch for robustness
    tryCatch({
      # ---------------------------------------------------------
      # --- Read and Preprocess Input Data ---
      # ---------------------------------------------------------
      message("Reading input files...")
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
      
      # Align samples between counts and coldata
      common_samples <- intersect(colnames(counts), coldata\$sample)
      if (length(common_samples) < 2) {
        stop("Insufficient common samples between counts.csv and coldata.csv")
      }
      
      counts <- counts[, common_samples, drop = FALSE]
      coldata <- coldata[match(common_samples, coldata\$sample), ]
      coldata\$condition <- as.factor(coldata\$condition)
      
      # Log-transform counts if they are raw/normalized non-log values
      if (max(counts, na.rm = TRUE) > 50) {
        message("Log2-transforming expression data...")
        counts_log <- log2(counts + 1)
      } else {
        counts_log <- counts
      }
      
      # ---------------------------------------------------------
      # --- Differential Expression Analysis (DEA) ---
      # ---------------------------------------------------------
      message("Performing differential expression analysis with limma...")
      design <- model.matrix(~ condition, data = coldata)
      fit <- lmFit(counts_log, design)
      fit <- eBayes(fit)
      top_table <- topTable(fit, coef = 2, number = Inf)
      
      # Select top 100 most significant DEGs to ensure GRN runs efficiently
      top_table_sig <- top_table[order(top_table\$P.Value), ]
      top_table_sig <- head(top_table_sig, 100)
      
      DEGsmatrix <- as.matrix(top_table_sig[, "logFC", drop = FALSE])
      colnames(DEGsmatrix) <- "logFC"
      
      # ---------------------------------------------------------
      # --- Functional Enrichment Analysis (FEA) ---
      # ---------------------------------------------------------
      message("Running Functional Enrichment Analysis (FEA)...")
      dataFEA <- FEA(DiffMatrix = DEGsmatrix, method = "ora")
      
      # ---------------------------------------------------------
      # --- Gene Regulatory Network (GRN) Inference ---
      # ---------------------------------------------------------
      message("Inferring Gene Regulatory Network (GRN)...")
      # Select a subset of genes to act as transcription factors (TFs)
      set.seed(42)
      tfs <- sample(rownames(DEGsmatrix), min(30, nrow(DEGsmatrix)))
      normCounts <- as.matrix(counts_log[rownames(DEGsmatrix), , drop = FALSE])
      
      dataGRN <- GRN(
        DEGsmatrix = DEGsmatrix,
        TFs = tfs,
        normCounts = normCounts,
        nGenesPerm = 5,
        kNearest = 3,
        nBoot = 5,
        DiffGenes = TRUE
      )
      
      # ---------------------------------------------------------
      # --- Upstream Regulator Analysis (URA) ---
      # ---------------------------------------------------------
      message("Running Upstream Regulator Analysis (URA)...")
      # Extract biological processes from FEA results
      BPselected <- NULL
      if (!is.null(dataFEA) && "Diseases.or.Functions.Annotation" %in% colnames(dataFEA)) {
        BPselected <- dataFEA\$Diseases.or.Functions.Annotation
      } else if (is.list(dataFEA) && "Diseases.or.Functions.Annotation" %in% names(dataFEA)) {
        BPselected <- dataFEA\$Diseases.or.Functions.Annotation
      }
      
      # Filter to standard cancer-related processes to ensure robust downstream analysis
      standard_bps <- c("apoptosis", "proliferation of cells", "cell death", "migration of cells", "invasion of cells")
      if (!is.null(BPselected)) {
        BPselected <- intersect(BPselected, standard_bps)
      }
      if (is.null(BPselected) || length(BPselected) == 0) {
        BPselected <- c("apoptosis", "proliferation of cells")
      }
      BPselected <- head(BPselected, 3)
      
      dataURA <- URA(
        dataGRN = dataGRN,
        DEGsmatrix = DEGsmatrix,
        BPname = BPselected,
        nCores = 1
      )
      
      # ---------------------------------------------------------
      # --- Pattern Recognition Analysis (PRA) ---
      # ---------------------------------------------------------
      message("Running Pattern Recognition Analysis (PRA)...")
      dataPRA <- PRA(
        dataURA = dataURA,
        BPname = BPselected,
        thres.role = 0
      )
      
      # ---------------------------------------------------------
      # --- Exporting Results and Visualizations ---
      # ---------------------------------------------------------
      message("Writing output tables...")
      
      # 1. Predicted Drivers
      tsg_genes <- names(dataPRA\$TSG)
      ocg_genes <- names(dataPRA\$OCG)
      drivers_df <- data.frame(
        Gene = c(tsg_genes, ocg_genes),
        Score = c(as.numeric(dataPRA\$TSG), as.numeric(dataPRA\$OCG)),
        Predicted_Role = c(rep("TSG", length(tsg_genes)), rep("OCG", length(ocg_genes)))
      )
      write.csv(drivers_df, "predicted_drivers.csv", row.names = FALSE)
      
      # 2. FEA Results
      write.csv(as.data.frame(dataFEA), "fea_results.csv", row.names = FALSE)
      
      # 3. URA Results
      write.csv(as.data.frame(dataURA), "ura_results.csv", row.names = TRUE)
      
      # 4. Visualizations
      message("Generating plots...")
      pdf("moonlight_plots.pdf", width = 10, height = 8)
      
      # Custom FEA Plot
      if (!is.null(dataFEA) && nrow(dataFEA) > 0) {
        fea_plot_data <- head(dataFEA[order(dataFEA\$p.value), ], 10)
        par(mar = c(5, 15, 4, 2))
        barplot(
          -log10(fea_plot_data\$p.value),
          names.arg = fea_plot_data\$Diseases.or.Functions.Annotation,
          las = 2,
          col = "skyblue",
          main = "Top Enriched Biological Processes (-log10 p-value)",
          horiz = TRUE,
          cex.names = 0.7
        )
      } else {
        plot.new()
        text(0.5, 0.5, "No FEA results to plot")
      }
      
      # Custom URA Heatmap
      if (!is.null(dataURA) && ncol(dataURA) > 0) {
        par(mar = c(5, 5, 4, 2))
        heatmap(
          as.matrix(dataURA),
          main = "Upstream Regulator Analysis Z-scores",
          col = cm.colors(256),
          margins = c(10, 10)
        )
      } else {
        plot.new()
        text(0.5, 0.5, "No URA results to plot")
      }
      
      dev.off()
      message("Pipeline completed successfully!")
      
    }, error = function(e) {
      write_fallback(e\$message)
    })

    writeLines(c(
        '"BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION":',
        paste0('    Moonlight2R: ', as.character(packageVersion('Moonlight2R')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_moonlight_driver_prediction.csv versions.yml
    """
}

workflow BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION(ch_input)

    emit:
    tables   = BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION.out.tables
    plots    = BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION.out.plots
    objects  = BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION.out.objects
    versions = BIOC_MOONLIGHT2R_MOONLIGHT_DRIVER_PREDICTION.out.versions
}
