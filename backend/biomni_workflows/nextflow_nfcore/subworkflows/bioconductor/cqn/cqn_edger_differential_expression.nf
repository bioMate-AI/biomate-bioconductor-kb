#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cqn — cqn_edger_differential_expression
// Perform differential expression analysis using edgeR with CQN-normalized offsets.
// Input: count_matrix.tsv, gene_lengths.tsv, gc_content.tsv, size_factors.tsv, sample_groups.tsv
// Container: quay.io/biocontainers/bioconductor-cqn:1.56.0--r45hdfd78af_0
// Requires: cqn, edgeR, scales
// Visualizations: MA plot
// QC: input validation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run conditional quantile normalization using cqn
//  * 2. [Input & Preparation] Construct an edgeR DGEList object
//  * 3. [Input & Preparation] Define the experimental design matrix
//  * 4. [Core Analysis] Assign the CQN glm.offset to the DGEList object
//  * 5. [Core Analysis] Estimate dispersion and fit the GLM
//  * 6. [Core Analysis] Perform likelihood ratio test and extract top differentially expressed genes

nextflow.enable.dsl = 2

process BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(cqn)
    library(scales)
    library(edgeR)
    
    # ------------------------------------------------------------------------------
    # 1. Read and Align User Input Files
    # ------------------------------------------------------------------------------
    
    # Read raw count matrix
    montgomery.subset <- as.matrix(read.table("count_matrix.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE))
    
    # Read gene lengths and GC content
    gene_lengths_df <- read.table("gene_lengths.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    gc_content_df <- read.table("gc_content.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    
    # Read size factors and sample groups
    size_factors_df <- read.table("size_factors.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    sample_groups_df <- read.table("sample_groups.tsv", header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
    
    # Align genes across counts, lengths, and GC content
    common_genes <- intersect(rownames(montgomery.subset), intersect(rownames(gene_lengths_df), rownames(gc_content_df)))
    montgomery.subset <- montgomery.subset[common_genes, , drop = FALSE]
    
    uCovar <- data.frame(
      length = gene_lengths_df[common_genes, 1],
      gccontent = gc_content_df[common_genes, 1],
      row.names = common_genes
    )
    
    # Align samples across counts, size factors, and sample groups
    common_samples <- intersect(colnames(montgomery.subset), intersect(rownames(size_factors_df), rownames(sample_groups_df)))
    montgomery.subset <- montgomery.subset[, common_samples, drop = FALSE]
    
    sizeFactors.subset <- size_factors_df[common_samples, 1]
    names(sizeFactors.subset) <- common_samples
    
    group_vector <- sample_groups_df[common_samples, 1]
    
    # Verify alignment integrity
    stopifnot(all(rownames(montgomery.subset) == rownames(uCovar)))
    stopifnot(colnames(montgomery.subset) == names(sizeFactors.subset))
    
    # ------------------------------------------------------------------------------
    # 2. Run Conditional Quantile Normalization (CQN)
    # ------------------------------------------------------------------------------
    
    cqn.subset <- cqn(montgomery.subset, lengths = uCovar\$length, 
                      x = uCovar\$gccontent, sizeFactors = sizeFactors.subset,
                      verbose = TRUE)
    
    # Save CQN object
    saveRDS(cqn.subset, "cqn_object.rds")
    
    # Calculate and save normalized RPKM values
    RPKM.cqn <- cqn.subset\$y + cqn.subset\$offset
    write.table(RPKM.cqn, "normalized_rpkm.tsv", sep = "\t", quote = FALSE, col.names = NA)
    
    # Generate CQN systematic effects plot
    pdf("cqn_effects_plot.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    cqnplot(cqn.subset, n = 1, xlab = "GC content", lty = 1, ylim = c(1, 7))
    cqnplot(cqn.subset, n = 2, xlab = "length", lty = 1, ylim = c(1, 7))
    dev.off()
    
    # ------------------------------------------------------------------------------
    # 3. Differential Expression Analysis with edgeR
    # ------------------------------------------------------------------------------
    
    d.mont <- DGEList(counts = montgomery.subset, lib.size = sizeFactors.subset, 
                      group = group_vector, genes = uCovar)
    
    design <- model.matrix(~ d.mont\$sample\$group)
    d.mont\$offset <- cqn.subset\$glm.offset
    d.mont.cqn <- estimateGLMCommonDisp(d.mont, design = design) 
    efit.cqn <- glmFit(d.mont.cqn, design = design)
    elrt.cqn <- glmLRT(efit.cqn, coef = 2)
    
    # Print top tags and summary to stdout
    cat("\n--- Top 2 Differentially Expressed Genes (CQN) ---\n")
    print(topTags(elrt.cqn, n = 2))
    
    cat("\n--- DecideTests Summary (CQN) ---\n")
    print(summary(decideTests(elrt.cqn)))
    
    # Save full differential expression results
    de_res <- topTags(elrt.cqn, n = Inf)\$table
    write.table(de_res, "de_results_cqn.tsv", sep = "\t", quote = FALSE, col.names = NA)
    
    # Save decideTests summary
    de_summary <- as.matrix(summary(decideTests(elrt.cqn)))
    write.table(de_summary, "de_summary_cqn.tsv", sep = "\t", quote = FALSE, col.names = NA)
    
    # ------------------------------------------------------------------------------
    # 4. Generate Diagnostic MA Plots (Standard vs CQN)
    # ------------------------------------------------------------------------------
    
    tryCatch({
      RPM <- sweep(log2(montgomery.subset + 1), 2, log2(sizeFactors.subset/10^6))
      RPKM.std <- sweep(RPM, 1, log2(uCovar\$length / 10^3))
    
      unique_groups <- unique(group_vector)
      if (length(unique_groups) >= 2) {
        grp1_samples <- colnames(montgomery.subset)[group_vector == unique_groups[1]]
        grp2_samples <- colnames(montgomery.subset)[group_vector == unique_groups[2]]
        
        whGenes <- which(rowMeans(RPKM.std) >= 2 & uCovar\$length >= 100)
        if (length(whGenes) > 0) {
          M.std <- rowMeans(RPKM.std[whGenes, grp1_samples, drop = FALSE]) - rowMeans(RPKM.std[whGenes, grp2_samples, drop = FALSE])
          A.std <- rowMeans(RPKM.std[whGenes, , drop = FALSE])
          M.cqn <- rowMeans(RPKM.cqn[whGenes, grp1_samples, drop = FALSE]) - rowMeans(RPKM.cqn[whGenes, grp2_samples, drop = FALSE])
          A.cqn <- rowMeans(RPKM.cqn[whGenes, , drop = FALSE])
          
          # Standard vs CQN MA Plot
          pdf("ma_plots.pdf", width = 10, height = 5)
          par(mfrow = c(1, 2))
          plot(A.std, M.std, cex = 0.5, pch = 16, xlab = "A", ylab = "M", 
               main = "Standard RPKM", ylim = c(-4, 4), xlim = c(0, 12), 
               col = alpha("black", 0.25))
          plot(A.cqn, M.cqn, cex = 0.5, pch = 16, xlab = "A", ylab = "M", 
               main = "CQN normalized RPKM", ylim = c(-4, 4), xlim = c(0, 12), 
               col = alpha("black", 0.25))
          dev.off()
          
          # GC-content Stratified MA Plot
          pdf("gc_ma_plots.pdf", width = 10, height = 5)
          par(mfrow = c(1, 2))
          gccontent <- uCovar\$gccontent[whGenes]
          whHigh <- which(gccontent > quantile(gccontent, 0.9, na.rm = TRUE))
          whLow <- which(gccontent < quantile(gccontent, 0.1, na.rm = TRUE))
          
          plot(A.std[whHigh], M.std[whHigh], cex = 0.2, pch = 16, xlab = "A", 
               ylab = "M", main = "Standard RPKM", 
               ylim = c(-4, 4), xlim = c(0, 12), col = "red")
          points(A.std[whLow], M.std[whLow], cex = 0.2, pch = 16, col = "blue")
          
          plot(A.cqn[whHigh], M.cqn[whHigh], cex = 0.2, pch = 16, xlab = "A", 
               ylab = "M", main = "CQN normalized RPKM", 
               ylim = c(-4, 4), xlim = c(0, 12), col = "red")
          points(A.cqn[whLow], M.cqn[whLow], cex = 0.2, pch = 16, col = "blue")
          dev.off()
        }
      }
    }, error = function(e) {
      warning("MA plotting step skipped or failed: ", e\$message)
    })
    
    cat("\nPipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION":',
        paste0('    cqn: ', as.character(packageVersion('cqn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cqn_edger_differential_expression.csv versions.yml
    """
}

workflow BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.tsv, gene_lengths.tsv, gc_content.tsv, size_factors.tsv, sample_groups.tsv ] ]

    main:
    BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_CQN_CQN_EDGER_DIFFERENTIAL_EXPRESSION.out.versions
}
