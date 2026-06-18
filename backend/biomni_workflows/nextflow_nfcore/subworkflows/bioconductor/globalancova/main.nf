#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GlobalAncova — global_ancova_standard
// Test the association of a single gene set or pathway with clinical groups, optionally adjusting for covariates, and visualize the gene-wise and subject-wise con
// Input: expression_matrix.csv, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-globalancova:4.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GlobalAncova
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run GlobalAncova on all genes or a specific pathway using
//  * 2. [Visualization & Output] Run GlobalAncova adjusting for clinical covariates

nextflow.enable.dsl = 2

process BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD {
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
    .bm_deps <- c("GlobalAncova", "Biobase")
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
    library(GlobalAncova)
    library(Biobase)
    
    # Set seed for reproducibility of permutation tests
    set.seed(123)
    
    # Read user input files
    if (!file.exists("expression_matrix.csv") || !file.exists("phenotype_data.csv")) {
      stop("Error: 'expression_matrix.csv' and/or 'phenotype_data.csv' not found in the working directory.")
    }
    
    expr_mat <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    pheno_data <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
    
    # Align samples between expression matrix and phenotype data
    common_samples <- intersect(colnames(expr_mat), rownames(pheno_data))
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between expression matrix columns and phenotype data rows.")
    }
    expr_mat <- expr_mat[, common_samples, drop = FALSE]
    pheno_data <- pheno_data[common_samples, , drop = FALSE]
    
    # Define gene sets dynamically from the expression matrix
    cellcycle <- head(rownames(expr_mat), min(50, nrow(expr_mat)))
    p53 <- head(rownames(expr_mat), min(30, nrow(expr_mat)))
    
    # Construct ExpressionSet
    adf <- new("AnnotatedDataFrame", data = pheno_data)
    golubX <- new("ExpressionSet", exprs = expr_mat, phenoData = adf)
    
    # Extract actual phenotype variables from user data
    primary_group <- pData(golubX)[[1]]
    if (ncol(pData(golubX)) > 1) {
      covariate_data <- pData(golubX)[[2]]
    } else {
      covariate_data <- NULL
    }
    
    # --- DOCUMENTED CODE STAGES ---
    
    # --- Run GlobalAncova on all genes or a specific pathway using ---
    ga.all <- GlobalAncova(xx=exprs(golubX), group=primary_group, covars=NULL, perm=100)
    ga.cc <- GlobalAncova(xx=exprs(golubX), group=primary_group, test.genes=cellcycle, method="both", perm=1000)
    
    # --- Run GlobalAncova adjusting for clinical covariates ---
    ga.cc.BMPB <- GlobalAncova(xx=exprs(golubX), group=primary_group, covars=covariate_data, test.genes=cellcycle, method="both", perm=1000)
    
    # Stage 3 & 4: Generate gene and subjects plots
    pdf("global_ancova_plots.pdf", width = 10, height = 8)
    Plot.genes(xx=expr_mat, group=primary_group, test.genes=p53)
    Plot.subjects(xx=expr_mat, group=primary_group, test.genes=p53, legendpos="bottomright")
    dev.off()
    
    # --- SAVE OUTPUTS ---
    saveRDS(ga.all, "ga_all.rds")
    saveRDS(ga.cc, "ga_cc.rds")
    saveRDS(ga.cc.BMPB, "ga_cc_BMPB.rds")
    
    # Helper to format and write ANOVA tables
    write_anova_csv <- function(ga_obj, filename) {
      anova_df <- as.data.frame(ga_obj\$ANOVA)
      if (!is.null(ga_obj\$test.result)) {
        for (stat_name in rownames(ga_obj\$test.result)) {
          anova_df[[stat_name]] <- ga_obj\$test.result[stat_name, 1]
        }
      }
      write.csv(anova_df, filename, row.names = TRUE)
    }
    
    write_anova_csv(ga.all, "ga_all_results.csv")
    write_anova_csv(ga.cc, "ga_cc_results.csv")
    write_anova_csv(ga.cc.BMPB, "ga_cc_BMPB_results.csv")
    
    cat("Pipeline completed successfully. Outputs saved to 'global_ancova_plots.pdf', 'ga_all_results.csv', 'ga_cc_results.csv', and 'ga_cc_BMPB_results.csv'.\n")

    writeLines(c(
        '"BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD":',
        paste0('    GlobalAncova: ', as.character(packageVersion('GlobalAncova')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_global_ancova_standard.csv versions.yml
    """
}

workflow BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, phenotype_data.csv ] ]

    main:
    BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD(ch_input)

    emit:
    tables   = BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD.out.tables
    plots    = BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD.out.plots
    objects  = BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD.out.objects
    versions = BIOC_GLOBALANCOVA_GLOBAL_ANCOVA_STANDARD.out.versions
}
