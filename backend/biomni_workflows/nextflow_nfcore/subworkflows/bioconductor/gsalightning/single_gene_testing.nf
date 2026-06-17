#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSALightning — single_gene_testing
// Perform single-gene association testing using fast permutation tests or Mann-Whitney U tests.
// Input: expression_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-gsalightning:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSALightning
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run single-gene permutation testing using permTestLight
//  * 2. [Core Analysis] Run single-gene Mann-Whitney U testing using wilcoxTest

nextflow.enable.dsl = 2

process BIOC_GSALIGHTNING_SINGLE_GENE_TESTING {
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
    .bm_deps <- c("GSALightning")
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
        library(GSALightning)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Read expression matrix (genes as rows, samples as columns)
        if (!file.exists("expression_matrix.csv")) {
          stop("Error: 'expression_matrix.csv' not found in the working directory.")
        }
        expression_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        expression <- as.matrix(expression_df)
        
        # Read sample metadata
        if (!file.exists("sample_metadata.csv")) {
          stop("Error: 'sample_metadata.csv' not found in the working directory.")
        }
        sampleInfo <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
        
        # ==========================================
        # 2. Data Preprocessing & Alignment
        # ==========================================
        
        # Ensure sampleInfo has a 'TN' column to match the documented code
        if (!"TN" %in% colnames(sampleInfo)) {
          # Attempt to find a column representing condition/grouping
          possible_cols <- c("condition", "group", "status", "class", "treatment", "type")
          found <- FALSE
          for (col in possible_cols) {
            if (col %in% colnames(sampleInfo)) {
              sampleInfo\$TN <- sampleInfo[[col]]
              found <- TRUE
              break
            }
          }
          if (!found) {
            # Fallback to the second column if no matching column name is found
            sampleInfo\$TN <- sampleInfo[[2]]
          }
        }
        
        # Align expression matrix columns with sample metadata rows
        sample_id_cols <- c("sample", "sample_id", "id", "SampleID", "Sample")
        sample_id_col <- intersect(sample_id_cols, colnames(sampleInfo))
        
        if (length(sample_id_col) > 0) {
          rownames(sampleInfo) <- sampleInfo[[sample_id_col[1]]]
          common_samples <- intersect(colnames(expression), rownames(sampleInfo))
          if (length(common_samples) == 0) {
            stop("Error: No matching sample IDs found between expression matrix and sample metadata.")
          }
          expression <- expression[, common_samples, drop = FALSE]
          sampleInfo <- sampleInfo[common_samples, , drop = FALSE]
        } else {
          if (ncol(expression) != nrow(sampleInfo)) {
            stop("Error: Number of columns in expression matrix does not match number of rows in sample metadata.")
          }
        }
        
        # Remove genes with zero sample variance (critical pitfall for GSALightning)
        gene_sds <- apply(expression, 1, sd, na.rm = TRUE)
        expression <- expression[!is.na(gene_sds) & gene_sds != 0, , drop = FALSE]
        
        # Ensure expression matrix is strictly numeric
        mode(expression) <- "numeric"
        
        # ==========================================
        # 3. Run Documented Workflow
        # ==========================================
        
        # Stage 1: Run single-gene permutation testing using permTestLight
        singleGeneAnalysis <- permTestLight(eset = expression, fac = factor(sampleInfo\$TN), nperm = 1000,  method = 'mean', verbose = TRUE)
        
        # Stage 2: Run single-gene Mann-Whitney U testing using wilcoxTest
        singleWilcox <- wilcoxTest(eset = expression, fac = factor(sampleInfo\$TN), tests = "unpaired")
        
        # ==========================================
        # 4. Save Outputs
        # ==========================================
        
        # Save tabular results
        write.csv(singleGeneAnalysis, "single_gene_permutation_results.csv", row.names = TRUE)
        write.csv(singleWilcox, "single_gene_wilcox_results.csv", row.names = TRUE)
        
        # Save RDS objects for downstream analysis
        saveRDS(singleGeneAnalysis, "single_gene_permutation_results.rds")
        saveRDS(singleWilcox, "single_gene_wilcox_results.rds")
        
        # Generate and save diagnostic p-value comparison plots
        p_cols_perm <- grep("^p-value", colnames(singleGeneAnalysis), value = TRUE)
        p_cols_wilcox <- grep("^p-value", colnames(singleWilcox), value = TRUE)
        
        if (length(p_cols_perm) > 0 && length(p_cols_wilcox) > 0) {
          pdf("single_gene_pvalue_comparison.pdf", width = 10, height = 5)
          par(mfrow = c(1, 2))
          hist(singleGeneAnalysis[, p_cols_perm[1]], 
               main = paste("Permutation Test\n", p_cols_perm[1]), 
               xlab = "P-value", 
               col = "skyblue", 
               border = "white")
          hist(singleWilcox[, p_cols_wilcox[1]], 
               main = paste("Wilcoxon Test\n", p_cols_wilcox[1]), 
               xlab = "P-value", 
               col = "salmon", 
               border = "white")
          dev.off()
        }

    writeLines(c(
        '"BIOC_GSALIGHTNING_SINGLE_GENE_TESTING":',
        paste0('    GSALightning: ', as.character(packageVersion('GSALightning')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_gene_testing.csv versions.yml
    """
}

workflow BIOC_GSALIGHTNING_SINGLE_GENE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_GSALIGHTNING_SINGLE_GENE_TESTING(ch_input)

    emit:
    tables   = BIOC_GSALIGHTNING_SINGLE_GENE_TESTING.out.tables
    plots    = BIOC_GSALIGHTNING_SINGLE_GENE_TESTING.out.plots
    objects  = BIOC_GSALIGHTNING_SINGLE_GENE_TESTING.out.objects
    versions = BIOC_GSALIGHTNING_SINGLE_GENE_TESTING.out.versions
}
