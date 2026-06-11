#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSRI — single_gene_set_analysis
// Estimate the number of regulated genes and calculate the GSRI for a single gene set using standard or custom statistical tests.
// Input: expression_data.RData, phenotypes.csv
// Container: quay.io/biocontainers/bioconductor-gsri:2.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, GSRI, limma
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load Expression Data and Phenotypes
//  * 2. [Visualization & Output] Define and Filter Gene Sets
//  * 3. [Visualization & Output] Run GSRI with Custom Tests and Parameters
//  * 4. [Visualization & Output] Save Results and Generate Plots

nextflow.enable.dsl = 2

process BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(Biobase)
    library(GSRI)
    library(GSEABase)
    library(limma)
    
    # ==========================================
    # --- Load Expression Data and Phenotypes ---
    # ==========================================
    
    # Load the expression data from the working directory
    load("expression_data.RData")
    
    # Identify the ExpressionSet or matrix object loaded from the RData file
    eset_name <- NULL
    for (obj in ls()) {
      if (is(get(obj), "ExpressionSet")) {
        eset_name <- obj
        break
      }
    }
    
    if (!is.null(eset_name)) {
      eset <- get(eset_name)
    } else {
      # Look for a matrix if no ExpressionSet is found
      matrix_name <- NULL
      for (obj in ls()) {
        if (is.matrix(get(obj))) {
          matrix_name <- obj
          break
        }
      }
      if (!is.null(matrix_name)) {
        exprs_mat <- get(matrix_name)
      } else {
        stop("Error: No ExpressionSet or matrix found in expression_data.RData")
      }
    }
    
    # Read the phenotypic metadata
    phenotypes_df <- read.csv("phenotypes.csv", stringsAsFactors = TRUE)
    
    # Align and construct/update the ExpressionSet object
    if (exists("eset")) {
      if (nrow(phenotypes_df) == ncol(eset)) {
        if (!is.null(rownames(phenotypes_df)) && all(rownames(phenotypes_df) %in% sampleNames(eset))) {
          phenotypes_df <- phenotypes_df[sampleNames(eset), , drop = FALSE]
        }
        pData(eset) <- phenotypes_df
      } else {
        stop("Error: Number of rows in phenotypes.csv does not match columns in ExpressionSet")
      }
    } else if (exists("exprs_mat")) {
      if (nrow(phenotypes_df) == ncol(exprs_mat)) {
        if (!is.null(rownames(phenotypes_df)) && all(rownames(phenotypes_df) %in% colnames(exprs_mat))) {
          phenotypes_df <- phenotypes_df[colnames(exprs_mat), , drop = FALSE]
        }
        eset <- ExpressionSet(assayData = exprs_mat, phenoData = AnnotatedDataFrame(phenotypes_df))
      } else {
        stop("Error: Number of rows in phenotypes.csv does not match columns in expression matrix")
      }
    }
    
    # Extract expression matrix and phenotype data frame
    exprs <- exprs(eset)
    phenotypes <- pData(phenoData(eset))
    
    # Dynamically identify phenotype columns to avoid hardcoding
    pheno_cols <- colnames(phenotypes)
    col_type <- pheno_cols[1]
    col_sex <- if (length(pheno_cols) > 1) pheno_cols[2] else pheno_cols[1]
    num_cols <- pheno_cols[sapply(phenotypes, is.numeric)]
    col_score <- if (length(num_cols) > 0) num_cols[1] else pheno_cols[1]
    
    # ==========================================
    # --- Define and Filter Gene Sets ---
    # ==========================================
    
    # Run GSRI on all probes
    gAllProbes <- gsri(eset, phenotypes[[col_type]])
    
    # Define a GeneSet and filter out control probes (e.g., Affymetrix AFFX controls)
    gs <- GeneSet(eset, setName="allGenes")
    ind <- grep("^AFFX", geneIds(gs), invert=TRUE)
    gsAllGenes <- gs[ind]
    
    # Run GSRI on the filtered gene set for both 'type' and 'sex' phenotypes
    gAllGenesType <- gsri(eset, phenotypes[[col_type]], gsAllGenes, name="allGenesType")
    gAllGenesSex <- gsri(exprs, phenotypes[[col_sex]], gsAllGenes, name="allGenesSex")
    
    # Define a custom GeneSetCollection representing the gene set of interest (e.g., chr17)
    # We select a subset of genes from the filtered gene set to represent this group
    chr17_genes <- geneIds(gsAllGenes)[1:min(12, length(geneIds(gsAllGenes)))]
    gsChr17 <- GeneSetCollection(GeneSet(chr17_genes, setName="chr17"))
    
    # Run GSRI on the custom gene set collection
    gChr17 <- gsri(eset, phenotypes[[col_type]], gsChr17)
    
    # ==========================================
    # --- Run GSRI with Custom Tests and Parameters ---
    # ==========================================
    
    # Categorize the continuous score variable into classes dynamically
    score_vals <- as.numeric(phenotypes[[col_score]])
    if (length(unique(score_vals[!is.na(score_vals)])) > 2) {
        phenotypes\$class <- cut(score_vals, breaks=3, labels=c("low", "medium", "high"))
    } else {
        phenotypes\$class <- as.factor(phenotypes[[col_score]])
    }
    
    # Run GSRI using the F-test (rowF)
    g3 <- gsri(eset, phenotypes\$class, gsChr17, test=rowF)
    
    # Run GSRI with custom parameters (nBoot, alpha, grenander)
    g3arg2 <- gsri(eset, phenotypes\$class, gsChr17, test=rowF, name="chr17_2", nBoot=50, alpha=0.1, grenander=FALSE)
    
    # Define a custom limma-based test function
    limmaTest <- function(exprs, groups, id, index, testArgs) {
        design <- cbind(offset=1, diff=groups)
        fit <- lmFit(exprs[ ,index], design)
        fit <- eBayes(fit)
        pval <- fit\$p.value[id,"diff"]
        return(pval)
    }
    
    # Run GSRI using the custom limma test
    g3Limma <- gsri(eset, phenotypes[[col_type]], gsChr17, test=limmaTest)
    
    # ==========================================
    # --- Save Results and Generate Plots ---
    # ==========================================
    
    # Save RDS objects of the GSRI results
    saveRDS(gAllProbes, "gAllProbes.rds")
    saveRDS(gAllGenesType, "gAllGenesType.rds")
    saveRDS(gAllGenesSex, "gAllGenesSex.rds")
    saveRDS(gChr17, "gChr17.rds")
    saveRDS(g3, "g3.rds")
    saveRDS(g3arg2, "g3arg2.rds")
    saveRDS(g3Limma, "g3Limma.rds")
    
    # Write text summary of the results
    sink("gsri_results_summary.txt")
    cat("==================================================\n")
    cat("GSRI Analysis Results Summary\n")
    cat("==================================================\n\n")
    
    cat("--- gAllProbes ---\n")
    print(gAllProbes)
    cat("\n")
    
    cat("--- gAllGenesType ---\n")
    print(gAllGenesType)
    cat("\n")
    
    cat("--- gAllGenesSex ---\n")
    print(gAllGenesSex)
    cat("\n")
    
    cat("--- gChr17 ---\n")
    print(gChr17)
    cat("\n")
    
    cat("--- g3 (F-test) ---\n")
    print(g3)
    cat("\n")
    
    cat("--- g3arg2 (Custom Parameters) ---\n")
    print(g3arg2)
    cat("\n")
    
    cat("--- g3Limma (Limma Test) ---\n")
    print(g3Limma)
    cat("\n")
    sink()
    
    # Plot the empirical cumulative p-value distribution and GSRI fit
    pdf("gsri_fit_plots.pdf", width=7, height=7)
    plot(g3)
    dev.off()

    writeLines(c(
        '"BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS":',
        paste0('    GSRI: ', as.character(packageVersion('GSRI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_gene_set_analysis.csv versions.yml
    """
}

workflow BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, phenotypes.csv ] ]

    main:
    BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS.out.tables
    plots    = BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS.out.plots
    objects  = BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS.out.objects
    versions = BIOC_GSRI_SINGLE_GENE_SET_ANALYSIS.out.versions
}
