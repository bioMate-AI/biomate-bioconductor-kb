#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LPE — lpe_differential_expression
// Identify differentially expressed genes between two microarray conditions with small replicate numbers using local pooled error and FDR adjustment.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-lpe:1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: LPE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess and normalize the intensity data using preprocess
//  * 2. [Core Analysis] Filter out control probes (e.g., AFFX)
//  * 3. [Core Analysis] Estimate baseline error distribution for each condition using baseOlig.error
//  * 4. [Core Analysis] Calculate local pooled error (LPE) z-statistics using lpe
//  * 5. [Core Analysis] Perform FDR correction using fdr.adjust

nextflow.enable.dsl = 2

process BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("LPE")
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
    
    # Set seed for reproducibility
    set.seed(0)
    
    # Load required library
    library(LPE)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input
    # ----------------------------------------------------------------------
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    
    # Read the expression matrix
    # Expected format: First column is Gene/Probe ID, followed by 6 replicate columns
    # (3 replicates for Condition 1, 3 replicates for Condition 2)
    input_data <- read.csv("expression_matrix.csv", stringsAsFactors = FALSE)
    
    if (ncol(input_data) < 7) {
      stop("Error: 'expression_matrix.csv' must contain at least 7 columns (1 ID column and 6 replicate columns).")
    }
    
    # Standardize column names and structure to match the documented workflow
    colnames(input_data)[1] <- "ID"
    Ley.subset <- input_data[, 1:7]
    
    # ----------------------------------------------------------------------
    # 2. Preprocess and Normalize
    # ----------------------------------------------------------------------
    Ley.normalized <- Ley.subset
    Ley.normalized[, 2:7] <- preprocess(Ley.subset[, 2:7], data.type = "MAS5")
    
    # Filter out Affymetrix control probes (IDs starting with "AFFX")
    Ley.final <- Ley.normalized[substring(Ley.normalized\$ID, 1, 4) != "AFFX", ]
    
    # ----------------------------------------------------------------------
    # 3. Estimate Baseline Error Distribution
    # ----------------------------------------------------------------------
    # Condition 1 (Naive / Columns 2:4)
    var.Naive <- baseOlig.error(Ley.final[, 2:4], q = 0.01)
    
    # Condition 2 (Activated / Columns 5:7)
    var.Activated <- baseOlig.error(Ley.final[, 5:7], q = 0.01)
    
    # ----------------------------------------------------------------------
    # 4. Calculate Local Pooled Error (LPE) z-statistics
    # ----------------------------------------------------------------------
    lpe.val <- data.frame(lpe(Ley.final[, 5:7], Ley.final[, 2:4],
                              var.Activated, var.Naive,
                              probe.set.name = Ley.final\$ID))
    
    # ----------------------------------------------------------------------
    # 5. Perform FDR Correction
    # ----------------------------------------------------------------------
    fdr.BH <- fdr.adjust(lpe.val, adjp = "BH")
    fdr.resamp <- fdr.adjust(lpe.val, adjp = "resamp", iterations = 2)
    Bonferroni.adjp <- fdr.adjust(lpe.val, adjp = "Bonferroni")
    
    # ----------------------------------------------------------------------
    # 6. Save Outputs and Generate Plots
    # ----------------------------------------------------------------------
    # Save processed data and statistics to CSV
    lpe_results_df <- data.frame(ID = rownames(lpe.val), lpe.val, row.names = NULL)
    write.csv(lpe_results_df, "lpe_results.csv", row.names = FALSE)
    
    fdr_bh_df <- data.frame(ID = rownames(fdr.BH), fdr.BH, row.names = NULL)
    write.csv(fdr_bh_df, "fdr_bh_results.csv", row.names = FALSE)
    
    write.csv(as.data.frame(fdr.resamp), "fdr_resamp_results.csv", row.names = FALSE)
    
    fdr_bonf_df <- data.frame(ID = rownames(Bonferroni.adjp), Bonferroni.adjp, row.names = NULL)
    write.csv(fdr_bonf_df, "fdr_bonferroni_results.csv", row.names = FALSE)
    
    # Save R objects for downstream analysis
    saveRDS(
      list(
        normalized_data = Ley.final,
        var_naive = var.Naive,
        var_activated = var.Activated,
        lpe_val = lpe.val,
        fdr_bh = fdr.BH,
        fdr_resamp = fdr.resamp,
        fdr_bonferroni = Bonferroni.adjp
      ),
      file = "lpe_pipeline_results.rds"
    )
    
    # Plot 1: Baseline Error Curves
    pdf("baseline_error_curves.pdf", width = 8, height = 6)
    plot(var.Naive\$A, var.Naive\$var.M, col = "blue", pch = 20, 
         xlab = "A (Average Intensity)", ylab = "Variance of M", 
         main = "Baseline Error Curves")
    points(var.Activated\$A, var.Activated\$var.M, col = "red", pch = 20)
    legend("topright", legend = c("Condition 1 (Naive)", "Condition 2 (Activated)"), 
           col = c("blue", "red"), pch = 20)
    dev.off()
    
    # Plot 2: Distribution of z-statistics
    pdf("z_statistics_distribution.pdf", width = 8, height = 6)
    hist(lpe.val\$z.stats, breaks = 50, col = "skyblue", 
         xlab = "z-statistic", main = "Distribution of LPE z-statistics")
    abline(v = c(-1.96, 1.96), col = "red", lty = 2)
    dev.off()

    writeLines(c(
        '"BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION":',
        paste0('    LPE: ', as.character(packageVersion('LPE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lpe_differential_expression.csv versions.yml
    """
}

workflow BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_LPE_LPE_DIFFERENTIAL_EXPRESSION.out.versions
}
