#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EMDomics — emdomics_distribution_analysis
// Perform supervised multi-class or two-class distribution analysis on transcriptomics data using Earth Mover's Distance (EMD), Kolmogorov-Smirnov (KS), and Crame
// Input: counts.csv, coldata.csv
// Container: 2.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EMDomics
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS {
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
    .bm_deps <- c("EMDomics")
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
    
    # Load required libraries
    library(EMDomics)
    
    # ==========================================
    # Stage 1: Load and Preprocess Input Data
    # ==========================================
    
    # Read expression data
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' or 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    } else {
      rownames(counts_df) <- counts_df[, 1]
      counts_df <- counts_df[, -1]
    }
    expr_matrix <- as.matrix(counts_df)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
      stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(expr_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching sample names found between counts.csv and coldata.csv.")
    }
    
    expr_matrix <- expr_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Create named vector of group labels
    labels <- coldata\$condition
    names(labels) <- coldata\$sample
    
    # Filter out genes with zero or extremely low variance to avoid calculation errors
    gene_vars <- apply(expr_matrix, 1, var, na.rm = TRUE)
    expr_matrix <- expr_matrix[gene_vars > 1e-5 & !is.na(gene_vars), , drop = FALSE]
    
    if (nrow(expr_matrix) == 0) {
      stop("No genes passed the variance filtering step.")
    }
    
    # If data appears to be raw counts (large integer values), perform CPM and log2 transformation
    if (max(expr_matrix, na.rm = TRUE) > 100) {
      message("Detected raw counts. Performing CPM normalization and log2 transformation...")
      col_sums <- colSums(expr_matrix, na.rm = TRUE)
      col_sums[col_sums == 0] <- 1
      expr_matrix <- t(t(expr_matrix) / col_sums) * 1e6
      expr_matrix <- log2(expr_matrix + 1)
    }
    
    # ==========================================
    # Stage 2: Run Distributional Analyses
    # ==========================================
    
    # Define number of permutations (using 50 for a balance of speed and accuracy)
    n_permutations <- 50
    
    message("Running Earth Mover's Distance (EMD) analysis...")
    results_emd <- calculate_emd(expr_matrix, labels, nperm = n_permutations, parallel = FALSE)
    
    message("Running Kolmogorov-Smirnov (KS) analysis...")
    results_ks <- calculate_ks(expr_matrix, labels, nperm = n_permutations, parallel = FALSE)
    
    message("Running Cramer von Mises (CVM) analysis...")
    results_cvm <- calculate_cvm(expr_matrix, labels, nperm = n_permutations, parallel = FALSE)
    
    # ==========================================
    # Stage 3: Export Tabular Results
    # ==========================================
    
    # 1. EMD Results
    emd_tab <- results_emd\$emd
    write.csv(emd_tab, "emd_results.csv", row.names = TRUE)
    
    # 2. Pairwise EMD Results (only applicable for multi-class analyses)
    if (!is.null(results_emd\$pairwise.emd.table)) {
      write.csv(results_emd\$pairwise.emd.table, "pairwise_emd_results.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message = "Pairwise comparison not applicable for 2-class analysis"), 
                "pairwise_emd_results.csv", row.names = FALSE)
    }
    
    # 3. KS Results
    ks_tab <- results_ks\$ks
    write.csv(ks_tab, "ks_results.csv", row.names = TRUE)
    
    # 4. CVM Results
    cvm_tab <- results_cvm\$cvm
    write.csv(cvm_tab, "cvm_results.csv", row.names = TRUE)
    
    # ==========================================
    # Stage 4: Generate Diagnostic Visualizations
    # ==========================================
    
    pdf("emdomics_plots.pdf", width = 8, height = 6)
    
    # --- EMD Plots ---
    # Find top significant gene by EMD q-value
    top_gene_emd <- rownames(emd_tab)[order(emd_tab[, "q-value"], -emd_tab[, "emd"])][1]
    if (!is.na(top_gene_emd)) {
      plot_emd_density(results_emd, top_gene_emd)
    }
    plot_emdperms(results_emd)
    plot_emdnull(results_emd)
    
    # --- KS Plots ---
    top_gene_ks <- rownames(ks_tab)[order(ks_tab[, "q-value"], -ks_tab[, "ks"])][1]
    if (!is.na(top_gene_ks)) {
      plot_ks_density(results_ks, top_gene_ks)
    }
    plot_ksperms(results_ks)
    plot_ksnull(results_ks)
    
    # --- CVM Plots ---
    top_gene_cvm <- rownames(cvm_tab)[order(cvm_tab[, "q-value"], -cvm_tab[, "cvm"])][1]
    if (!is.na(top_gene_cvm)) {
      plot_cvm_density(results_cvm, top_gene_cvm)
    }
    plot_cvmperms(results_cvm)
    plot_cvmnull(results_cvm)
    
    dev.off()
    
    message("EMDomics pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS":',
        paste0('    EMDomics: ', as.character(packageVersion('EMDomics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_emdomics_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_EMDOMICS_EMDOMICS_DISTRIBUTION_ANALYSIS.out.versions
}
