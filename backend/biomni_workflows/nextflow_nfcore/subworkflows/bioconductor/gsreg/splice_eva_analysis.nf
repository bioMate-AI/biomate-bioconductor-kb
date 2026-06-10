#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSReg — splice_eva_analysis
// Detect alternative splicing events (SEVA) using junction expression and gene expression data.
// Input: junc.RPM.Simulated.csv, geneExrsGSReg.csv, phenotypes.csv
// Container: quay.io/biocontainers/bioconductor-gsreg:1.44.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSReg, GenomicRanges, Homo.sapiens, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute junction overlap matrices using GSReg.overlapJunction
//  * 2. [Core Analysis] Run Splice-EVA analysis using GSReg.SEVA to calculate splicing dysregulation p-values

nextflow.enable.dsl = 2

process BIOC_GSREG_SPLICE_EVA_ANALYSIS {
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
    library(GSReg)
    library(Homo.sapiens)
    library(org.Hs.eg.db)
    library(GenomicRanges)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read Junction expression matrix
    junc.RPM.Simulated <- as.matrix(read.csv("junc.RPM.Simulated.csv", row.names = 1, check.names = FALSE))
    
    # Read Gene expression matrix
    geneExrsGSReg <- as.matrix(read.csv("geneExrsGSReg.csv", row.names = 1, check.names = FALSE))
    
    # Read Phenotypes
    pheno_data <- read.csv("phenotypes.csv", header = FALSE, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Parse phenotypes into a binary factor vector
    if (ncol(pheno_data) == 1) {
      # Single column: check if first row is a header
      first_val <- pheno_data[1, 1]
      # If first row is a header, re-read with header = TRUE
      if (first_val %in% c("phenotype", "class", "group", "status", "y")) {
        pheno_data <- read.csv("phenotypes.csv", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)
        phenotypes <- as.factor(pheno_data[[1]])
      } else {
        phenotypes <- as.factor(pheno_data[[1]])
      }
    } else {
      # Multiple columns: assume column 1 is Sample ID, column 2 is Phenotype
      # Check if first row is header
      if (pheno_data[1, 1] %in% c("sample", "id", "sample_id", "gsm")) {
        pheno_data <- read.csv("phenotypes.csv", header = TRUE, stringsAsFactors = FALSE, check.names = FALSE)
        phenotypes <- as.factor(pheno_data[[2]])
        names(phenotypes) <- pheno_data[[1]]
      } else {
        phenotypes <- as.factor(pheno_data[[2]])
        names(phenotypes) <- pheno_data[[1]]
      }
    }
    
    # Align samples across all inputs
    common_samples <- intersect(colnames(junc.RPM.Simulated), colnames(geneExrsGSReg))
    if (!is.null(names(phenotypes))) {
      common_samples <- intersect(common_samples, names(phenotypes))
      phenotypes <- phenotypes[common_samples]
    } else {
      # If no names, assume order matches the expression matrices
      common_samples <- common_samples[1:min(length(common_samples), length(phenotypes))]
      phenotypes <- phenotypes[1:length(common_samples)]
    }
    
    junc.RPM.Simulated <- junc.RPM.Simulated[, common_samples, drop = FALSE]
    geneExrsGSReg <- geneExrsGSReg[, common_samples, drop = FALSE]
    
    # ==========================================
    # 2. Run Documented Workflow
    # ==========================================
    
    # Compute junction overlap matrices
    overlapMat <- GSReg.overlapJunction(juncExprs =  junc.RPM.Simulated, geneexpr = geneExrsGSReg)
    
    # Run Splice-EVA analysis to calculate splicing dysregulation p-values
    SEVAjunc <- GSReg.SEVA(juncExprs = junc.RPM.Simulated, phenoVect = phenotypes, geneexpr = geneExrsGSReg)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save RDS objects of the raw results
    saveRDS(overlapMat, file = "overlapMat.rds")
    saveRDS(SEVAjunc, file = "SEVAjunc.rds")
    
    # Extract and save meaningful results as a CSV table
    if (length(SEVAjunc) > 0) {
      seva_results <- data.frame(
        Gene = names(SEVAjunc),
        E1 = sapply(SEVAjunc, function(x) if (!is.null(x\$E1)) x\$E1 else NA),
        E2 = sapply(SEVAjunc, function(x) if (!is.null(x\$E2)) x\$E2 else NA),
        zscore = sapply(SEVAjunc, function(x) if (!is.null(x\$zscore)) x\$zscore else NA),
        pvalue = sapply(SEVAjunc, function(x) if (!is.null(x\$pvalue)) x\$pvalue else NA),
        pvalueTotal = sapply(SEVAjunc, function(x) if (!is.null(x\$pvalueTotal)) x\$pvalueTotal else NA),
        stringsAsFactors = FALSE
      )
      write.csv(seva_results, file = "SEVA_results.csv", row.names = FALSE)
      
      # Generate a PDF plot of the p-value distribution
      pdf("SEVA_pvalues_histogram.pdf", width = 6, height = 6)
      hist(seva_results\$pvalue, breaks = 20, 
           main = "P-value Histogram of Splice-EVA", 
           xlab = "p-value", col = "skyblue", border = "white")
      dev.off()
    }
    
    cat("Pipeline completed successfully. Outputs saved to 'overlapMat.rds', 'SEVAjunc.rds', 'SEVA_results.csv', and 'SEVA_pvalues_histogram.pdf'.\n")

    writeLines(c(
        '"BIOC_GSREG_SPLICE_EVA_ANALYSIS":',
        paste0('    GSReg: ', as.character(packageVersion('GSReg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splice_eva_analysis.csv versions.yml
    """
}

workflow BIOC_GSREG_SPLICE_EVA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ junc.RPM.Simulated.csv, geneExrsGSReg.csv, phenotypes.csv ] ]

    main:
    BIOC_GSREG_SPLICE_EVA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSREG_SPLICE_EVA_ANALYSIS.out.tables
    plots    = BIOC_GSREG_SPLICE_EVA_ANALYSIS.out.plots
    objects  = BIOC_GSREG_SPLICE_EVA_ANALYSIS.out.objects
    versions = BIOC_GSREG_SPLICE_EVA_ANALYSIS.out.versions
}
