#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EBSeq — gene_de_two_conditions
// Identify differentially expressed genes between two biological conditions using empirical Bayes modeling.
// Input: gene_counts.csv, sample_conditions.csv
// Container: quay.io/biocontainers/bioconductor-ebseq:2.8.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBSeq
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate sample normalization factors using MedianNorm. 2. Run the empirical Bayes test for two conditions using EBTest. 3. Extra

nextflow.enable.dsl = 2

process BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS {
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
    
    # Load required library
    library(EBSeq)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    if (!file.exists("gene_counts.csv")) {
      stop("Error: gene_counts.csv not found in the working directory.")
    }
    if (!file.exists("sample_conditions.csv")) {
      stop("Error: sample_conditions.csv not found in the working directory.")
    }
    
    # Read raw gene counts matrix
    GeneMat <- as.matrix(read.csv("gene_counts.csv", row.names = 1, check.names = FALSE))
    
    # Read sample conditions vector robustly (handling potential headers)
    cond_raw <- read.csv("sample_conditions.csv", header = FALSE, stringsAsFactors = FALSE)
    if (tolower(cond_raw[1, 1]) %in% c("condition", "group", "class", "status", "sample", "x")) {
      Conditions_factor <- as.factor(cond_raw[-1, 1])
    } else {
      Conditions_factor <- as.factor(cond_raw[, 1])
    }
    
    # Verify dimensions match
    if (ncol(GeneMat) != length(Conditions_factor)) {
      stop(paste("Error: Number of columns in gene_counts.csv (", ncol(GeneMat), 
                 ") does not match the number of samples in sample_conditions.csv (", 
                 length(Conditions_factor), ").", sep=""))
    }
    
    # ==========================================
    # 2. Calculate Sample Normalization Factors
    # ==========================================
    Sizes=MedianNorm(GeneMat)
    
    # ==========================================
    # 3. Run Empirical Bayes Test (Two Conditions)
    # ==========================================
    EBOut=EBTest(Data=GeneMat, Conditions=Conditions_factor, sizeFactors=Sizes, maxround=5)
    
    # ==========================================
    # 4. Extract DE Results and Posterior Probabilities
    # ==========================================
    EBDERes=GetDEResults(EBOut, FDR=0.05)
    
    # ==========================================
    # 5. Calculate Posterior Fold Changes
    # ==========================================
    GeneFC=PostFC(EBOut)
    
    # ==========================================
    # 6. Check EM Convergence and Model Fit Diagnostics
    # ==========================================
    # Print EM convergence parameters to console
    cat("=== EM Convergence Parameters ===\n")
    cat("Alpha:\n")
    print(EBOut\$Alpha)
    cat("\nBeta:\n")
    print(EBOut\$Beta)
    cat("\nP:\n")
    print(EBOut\$P)
    
    # Save EM parameters to a text file
    sink("em_convergence_parameters.txt")
    cat("=== Alpha ===\n")
    print(EBOut\$Alpha)
    cat("\n=== Beta ===\n")
    print(EBOut\$Beta)
    cat("\n=== P ===\n")
    print(EBOut\$P)
    sink()
    
    # Generate and save diagnostic plots
    pdf("post_vs_raw_fc.pdf", width=7, height=7)
    PlotPostVsRawFC(EBOut,GeneFC)
    dev.off()
    
    pdf("qq_plots.pdf", width=10, height=5)
    par(mfrow=c(1,2))
    QQP(EBOut)
    dev.off()
    
    pdf("density_histograms.pdf", width=10, height=5)
    par(mfrow=c(1,2))
    DenNHist(EBOut)
    dev.off()
    
    # ==========================================
    # 7. Write Output Files
    # ==========================================
    # Save RDS objects for downstream analysis
    saveRDS(EBOut, "EBOut.rds")
    saveRDS(EBDERes, "EBDERes.rds")
    saveRDS(GeneFC, "GeneFC.rds")
    
    # Save DE genes list
    write.csv(data.frame(Gene = EBDERes\$DEfound), "de_genes.csv", row.names = FALSE)
    
    # Save Posterior Probabilities Matrix
    write.csv(EBDERes\$PPMat, "posterior_probabilities.csv", row.names = TRUE)
    
    # Save DE Status for all genes
    write.csv(data.frame(Gene = names(EBDERes\$Status), Status = EBDERes\$Status), "de_status.csv", row.names = FALSE)
    
    # Save Fold Changes (Posterior and Real)
    fc_df <- data.frame(
      Gene = names(GeneFC\$PostFC),
      PostFC = GeneFC\$PostFC,
      RealFC = GeneFC\$RealFC,
      Direction = GeneFC\$Direction,
      stringsAsFactors = FALSE
    )
    write.csv(fc_df, "fold_changes.csv", row.names = FALSE)
    
    cat("\nPipeline completed successfully. All outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS":',
        paste0('    EBSeq: ', as.character(packageVersion('EBSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_de_two_conditions.csv versions.yml
    """
}

workflow BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_counts.csv, sample_conditions.csv ] ]

    main:
    BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS(ch_input)

    emit:
    tables   = BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS.out.tables
    plots    = BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS.out.plots
    objects  = BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS.out.objects
    versions = BIOC_EBSEQ_GENE_DE_TWO_CONDITIONS.out.versions
}
