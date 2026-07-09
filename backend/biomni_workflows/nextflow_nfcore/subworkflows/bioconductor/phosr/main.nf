#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhosR — batch_correction
// Correct for batch effects across multiple runs or datasets using stably phosphorylated sites (SPSs) as negative controls.
// Input: imputed_quantification_matrix.csv, sample_batches.csv
// Container: quay.io/biocontainers/bioconductor-phosr:1.20.0--r45hdfd78af_0
// R packages: SummarizedExperiment, annotate, calibrate, ClueR, directpa, ggally, ggplot2, ggpubr, PhosR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_PHOSR_BATCH_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-phosr:1.20.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SummarizedExperiment", "annotate", "calibrate", "ClueR", "directpa", "ggally", "ggplot2", "ggpubr", "PhosR")
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
    library(PhosR)
    library(SummarizedExperiment)
    library(ggplot2)
    library(ggpubr)
    
    # ==========================================
    # --- Read User Input Files ---
    # ==========================================
    message("Reading input files...")
    if (!file.exists("imputed_quantification_matrix.csv")) {
      stop("Error: 'imputed_quantification_matrix.csv' not found in the working directory.")
    }
    if (!file.exists("sample_batches.csv")) {
      stop("Error: 'sample_batches.csv' not found in the working directory.")
    }
    
    quant_mat <- read.csv("imputed_quantification_matrix.csv", row.names = 1, check.names = FALSE)
    batches_df <- read.csv("sample_batches.csv", stringsAsFactors = FALSE)
    
    # Align samples between quantification matrix and batch metadata
    common_samples <- intersect(colnames(quant_mat), batches_df\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between the quantification matrix columns and the sample_batches.csv 'sample' column.")
    }
    
    quant_mat <- quant_mat[, common_samples, drop = FALSE]
    batches_df <- batches_df[match(common_samples, batches_df\$sample), ]
    
    # ==========================================
    # --- Construct PhosphoExperiment Object ---
    # ==========================================
    message("Constructing PhosphoExperiment object...")
    
    # Helper function to safely parse row names (e.g., "Uniprot;GeneSymbol;ResidueSite;Sequence")
    safe_split <- function(x, index, default = "NA") {
      parts <- strsplit(x, ";")[[1]]
      if (length(parts) >= index) {
        return(parts[index])
      } else {
        return(default)
      }
    }
    
    gene_symbols <- sapply(rownames(quant_mat), safe_split, index = 2, default = "Unknown")
    residue_site <- sapply(rownames(quant_mat), safe_split, index = 3, default = "S0")
    residues <- gsub("[0-9]", "", residue_site)
    sites_num <- as.numeric(gsub("[A-Z]", "", residue_site))
    # Fallback for NA sites
    sites_num[is.na(sites_num)] <- 0
    sequences <- sapply(rownames(quant_mat), safe_split, index = 4, default = "AAAAAAAAAAAAAAA")
    
    ppe <- PhosphoExperiment(
      assays = list(Quantification = as.matrix(quant_mat)),
      GeneSymbol = gene_symbols,
      Residue = residues,
      Site = sites_num,
      Sequence = sequences
    )
    
    # Define sites representation
    sites = paste(sapply(GeneSymbol(ppe), function(x)x),";",
                     sapply(Residue(ppe), function(x)x),
                     sapply(Site(ppe), function(x)x),
                     ";", sep = "")
    
    # ==========================================
    # --- Generate Custom SPSs using getSPS ---
    # ==========================================
    message("Generating custom Stably Phosphorylated Sites (SPSs)...")
    
    # Split the PhosphoExperiment object into a list by batch to find stable sites across runs
    batches <- unique(batches_df\$batch)
    ppe.list <- list()
    cond.list <- list()
    
    for (i in seq_along(batches)) {
      b <- batches[i]
      samples_b <- batches_df\$sample[batches_df\$batch == b]
      ppe_sub <- ppe[, samples_b]
      
      batch_key <- paste0("batch", i)
      ppe.list[[batch_key]] <- ppe_sub
      cond.list[[batch_key]] <- batches_df\$group[batches_df\$batch == b]
    }
    
    # Run getSPS as documented
    inhouse_SPSs <- getSPS(ppe.list, conds = cond.list)
    
    # Determine the final set of SPSs to use as negative controls
    if (length(inhouse_SPSs) == 0) {
      message("Warning: No overlapping SPSs found by getSPS. Using fallback stably phosphorylated sites based on low variance.")
      # Fallback: use 10% lowest variance sites across all samples
      vars <- apply(SummarizedExperiment::assay(ppe, "Quantification"), 1, var)
      cutoff <- quantile(vars, 0.1, na.rm = TRUE)
      SPSs <- sites[which(vars <= cutoff)]
    } else {
      SPSs <- inhouse_SPSs
    }
    
    # ==========================================
    # --- Define Design Matrix and Run RUVphospho ---
    # ==========================================
    message("Running batch correction using RUVphospho...")
    
    grps <- batches_df\$group
    design = model.matrix(~ grps - 1)
    
    ctl = which(sites %in% SPSs)
    
    # Ensure ctl is not empty to prevent RUVphospho from failing
    if (length(ctl) == 0) {
      message("Warning: Control indices vector is empty. Falling back to top 100 lowest variance sites.")
      vars <- apply(SummarizedExperiment::assay(ppe, "Quantification"), 1, var)
      ctl <- order(vars)[1:min(100, length(vars))]
    }
    
    # Run RUVphospho exactly as documented
    ppe = RUVphospho(ppe, M = design, k = 3, ctl = ctl)
    
    # ==========================================
    # --- Generate Diagnostic Plots and Save Outputs ---
    # ==========================================
    message("Generating diagnostic plots and saving results...")
    
    # Save normalized quantification matrix
    norm_mat <- SummarizedExperiment::assay(ppe, "normalised")
    write.csv(norm_mat, "normalized_quantification_matrix.csv", row.names = TRUE)
    
    # Save the full PhosphoExperiment object
    saveRDS(ppe, "batch_corrected_ppe.rds")
    
    # Generate and save QC plots (PCA and Dendrogram)
    pdf("batch_correction_qc.pdf", width = 12, height = 10)
    
    # 1. PCA Comparison
    p1_pca <- plotQC(SummarizedExperiment::assay(ppe, "Quantification"), 
                     labels = colnames(ppe), 
                     panel = "pca", 
                     grps = grps) + 
              ggplot2::ggtitle("PCA: Before Batch Correction")
    
    p2_pca <- plotQC(SummarizedExperiment::assay(ppe, "normalised"), 
                     labels = colnames(ppe), 
                     panel = "pca", 
                     grps = grps) + 
              ggplot2::ggtitle("PCA: After Batch Correction")
    
    # 2. Dendrogram Comparison
    p1_dend <- plotQC(SummarizedExperiment::assay(ppe, "Quantification"), 
                      labels = colnames(ppe), 
                      panel = "dendrogram", 
                      grps = grps) + 
               ggplot2::ggtitle("Dendrogram: Before Batch Correction")
    
    p2_dend <- plotQC(SummarizedExperiment::assay(ppe, "normalised"), 
                      labels = colnames(ppe), 
                      panel = "dendrogram", 
                      grps = grps) + 
               ggplot2::ggtitle("Dendrogram: After Batch Correction")
    
    # Arrange and print plots
    print(ggpubr::ggarrange(p1_pca, p2_pca, p1_dend, p2_dend, nrow = 2, ncol = 2))
    dev.off()
    
    message("Pipeline completed successfully!")
    message("Outputs written:")
    message("  - normalized_quantification_matrix.csv")
    message("  - batch_corrected_ppe.rds")
    message("  - batch_correction_qc.pdf")
    # ── BIOC_QC_HARNESS — Phase 3c bulk adoption (missing-value handling) ───
    # Defensive scan: list every *.rds the workflow produced, load each one,
    # compute NA fraction across numeric cells where the artifact is a
    # matrix or data.frame. Report max NA fraction across artifacts.
    # Threshold from bioc_missing_value_handling: < 5% pass.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()
    .na_fracs <- numeric(0)
    .scanned_files <- character(0)
    for (.rds_file in list.files(".", pattern = "\\\\.rds\$", recursive = FALSE)) {
      .obj <- tryCatch(readRDS(.rds_file), error = function(e) NULL)
      .mat <- if (is.matrix(.obj) || is.data.frame(.obj)) .obj else NULL
      if (!is.null(.mat)) {
        .vals <- suppressWarnings(as.numeric(as.matrix(.mat)))
        if (length(.vals) > 0) {
          .na_fracs <- c(.na_fracs, mean(is.na(.vals)))
          .scanned_files <- c(.scanned_files, .rds_file)
        }
      }
    }
    .na_max <- if (length(.na_fracs) > 0) round(max(.na_fracs), 4) else NA_real_
    .gates_by_label[["missing-value handling"]] <- list(
      gate_row = "bioc_missing_value_handling",
      metric_name = "na_fraction_remaining",
      metric_value = .na_max,
      passes = isTRUE(is.finite(.na_max) && .na_max < 0.05),
      status = if (is.finite(.na_max)) paste0("computed (scanned ", length(.scanned_files), " rds files)")
               else "not_computed (no matrix/data.frame .rds artifact present)"
    )
    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_PHOSR_BATCH_CORRECTION",
      domain  = "bioconductor",
      declared_qc_steps = c("missing-value handling"),
      gates_by_label = .gates_by_label,
      evidence_tier = "SILVER (Lazar 2013 NAR; <5% community convention)",
      harness_version = "0.1.0-bulk-mv"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_PHOSR_BATCH_CORRECTION":',
        paste0('        PhosR: ', as.character(packageVersion("PhosR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_correction.csv versions.yml
    """
}

workflow BIOC_PHOSR_BATCH_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ imputed_quantification_matrix.csv, sample_batches.csv ] ]

    main:
    BIOC_PHOSR_BATCH_CORRECTION(ch_input)

    emit:
    tables   = BIOC_PHOSR_BATCH_CORRECTION.out.tables
    plots    = BIOC_PHOSR_BATCH_CORRECTION.out.plots
    objects  = BIOC_PHOSR_BATCH_CORRECTION.out.objects
    versions = BIOC_PHOSR_BATCH_CORRECTION.out.versions
}
