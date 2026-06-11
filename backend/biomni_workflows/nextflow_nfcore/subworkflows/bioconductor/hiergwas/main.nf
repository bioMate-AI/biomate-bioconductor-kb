#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hierGWAS — hierarchical_gwas_analysis
// Perform hierarchical clustering, multi-split LASSO regression, hierarchical testing, and explained variance computation on GWAS SNP data.
// Input: genotype_matrix.txt, phenotype_vector.txt, covariates.txt
// Container: quay.io/biocontainers/bioconductor-hiergwas:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: hierGWAS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and prepare genotype, phenotype, and covariate data
//  * 2. [Core Analysis] Cluster SNPs hierarchically per chromosome using cluster.snp
//  * 3. [Core Analysis] Perform multiple sample splitting and LASSO regression using multisplit
//  * 4. [Core Analysis] Perform hierarchical testing of SNPs using test.hierarchy
//  * 5. [Core Analysis] Compute explained variance (R2) for a group of SNPs using compute.r2

nextflow.enable.dsl = 2

process BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(hierGWAS)
    
    # ==========================================
    # 1. Load and Prepare Input Data
    # ==========================================
    
    # Robustly read genotype matrix
    if (!file.exists("genotype_matrix.txt")) {
      stop("Error: genotype_matrix.txt not found in the working directory.")
    }
    first_line_geno <- readLines("genotype_matrix.txt", n = 1)
    has_header_geno <- !all(grepl("^[0-9eE\\\\.\\\\-\\\\s,;\\t]+\$", first_line_geno))
    sim.geno <- data.matrix(read.table("genotype_matrix.txt", header = has_header_geno))
    
    # Robustly read phenotype vector
    if (!file.exists("phenotype_vector.txt")) {
      stop("Error: phenotype_vector.txt not found in the working directory.")
    }
    first_line_pheno <- readLines("phenotype_vector.txt", n = 1)
    has_header_pheno <- !all(grepl("^[0-9eE\\\\.\\\\-\\\\s,;\\t]+\$", first_line_pheno))
    sim.pheno_df <- read.table("phenotype_vector.txt", header = has_header_pheno)
    sim.pheno <- as.numeric(sim.pheno_df[[1]])
    
    # Robustly read covariates (optional)
    sim.covar <- NULL
    if (file.exists("covariates.txt") && file.info("covariates.txt")\$size > 0) {
      first_line_cov <- readLines("covariates.txt", n = 1)
      has_header_cov <- !all(grepl("^[0-9eE\\\\.\\\\-\\\\s,;\\t]+\$", first_line_cov))
      sim.covar <- data.matrix(read.table("covariates.txt", header = has_header_cov))
    }
    
    # Determine SNP indices dynamically based on the input dimensions
    p <- ncol(sim.geno)
    if (p < 2) {
      stop("Error: Genotype matrix must contain at least 2 SNPs (columns).")
    }
    half_p <- floor(p / 2)
    
    # ==========================================
    # 2. Hierarchical Clustering of SNPs
    # ==========================================
    
    # Cluster SNPs in chromosome 1 (first half of SNPs)
    SNPindex.chrom1 <- seq(1, half_p)
    dendr.chrom1 <- cluster.snp(sim.geno, SNP_index = SNPindex.chrom1)
    
    # Cluster SNPs in chromosome 2 (second half of SNPs)
    SNPindex.chrom2 <- seq(half_p + 1, p)
    dendr.chrom2 <- cluster.snp(sim.geno, SNP_index = SNPindex.chrom2)
    
    # ==========================================
    # 3. Multiple Sample Splitting & LASSO
    # ==========================================
    
    res.multisplit <- multisplit(sim.geno, sim.pheno, covar = sim.covar)
    
    # ==========================================
    # 4. Hierarchical Testing of SNPs
    # ==========================================
    
    # Test hierarchy for chromosome 1
    result.chrom1 <- test.hierarchy(sim.geno, sim.pheno, dendr.chrom1, res.multisplit,
                                    covar = sim.covar, SNP_index = SNPindex.chrom1)
    
    # Test hierarchy for chromosome 2 (using dendr.chrom2 to match SNPindex.chrom2)
    result.chrom2 <- test.hierarchy(sim.geno, sim.pheno, dendr.chrom2, res.multisplit,
                                    covar = sim.covar, SNP_index = SNPindex.chrom2,
                                    global.test = FALSE, verbose = FALSE)
    
    # ==========================================
    # 5. Computation of Explained Variance (R2)
    # ==========================================
    
    # Select a group of SNPs (e.g., the last 10 SNPs, or fewer if p < 10)
    start_idx <- max(1, p - 9)
    SNP_index <- seq(start_idx, p)
    res.r2 <- compute.r2(sim.geno, sim.pheno, res.multisplit, covar = sim.covar, SNP_index = SNP_index)
    
    # ==========================================
    # 6. Export Results and Visualizations
    # ==========================================
    
    # Save R objects
    saveRDS(dendr.chrom1, "dendr_chrom1.rds")
    saveRDS(dendr.chrom2, "dendr_chrom2.rds")
    saveRDS(res.multisplit, "res_multisplit.rds")
    saveRDS(result.chrom1, "result_chrom1.rds")
    saveRDS(result.chrom2, "result_chrom2.rds")
    
    # Helper function to format hierarchical testing results into a data frame
    format_results <- function(res) {
      if (is.null(res) || length(res) == 0) {
        return(data.frame(Group = character(), P_Value = numeric(), SNPs = character()))
      }
      df_list <- lapply(seq_along(res), function(i) {
        snps_str <- paste(res[[i]]\$label, collapse = ",")
        data.frame(
          Group = paste0("Group_", i),
          P_Value = res[[i]]\$pval,
          SNPs = snps_str,
          stringsAsFactors = FALSE
        )
      })
      do.call(rbind, df_list)
    }
    
    # Save CSV tables of significant groups
    write.csv(format_results(result.chrom1), "significant_snps_chrom1.csv", row.names = FALSE)
    write.csv(format_results(result.chrom2), "significant_snps_chrom2.csv", row.names = FALSE)
    
    # Save explained variance
    writeLines(as.character(res.r2), "explained_variance_r2.txt")
    
    # Plot and save dendrograms
    pdf("dendrograms.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    plot(dendr.chrom1, main = "Dendrogram Chromosome 1", sub = "", xlab = "SNP Index")
    plot(dendr.chrom2, main = "Dendrogram Chromosome 2", sub = "", xlab = "SNP Index")
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS":',
        paste0('    hierGWAS: ', as.character(packageVersion('hierGWAS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hierarchical_gwas_analysis.csv versions.yml
    """
}

workflow BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotype_matrix.txt, phenotype_vector.txt, covariates.txt ] ]

    main:
    BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS.out.tables
    plots    = BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS.out.plots
    objects  = BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS.out.objects
    versions = BIOC_HIERGWAS_HIERARCHICAL_GWAS_ANALYSIS.out.versions
}
