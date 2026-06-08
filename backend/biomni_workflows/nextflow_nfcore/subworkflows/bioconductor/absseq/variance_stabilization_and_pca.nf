#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ABSSeq — variance_stabilization_and_pca
// Stabilize count variances across expression levels using the aFold model and perform Principal Component Analysis (PCA) for exploratory data analysis.
// Input: counts.tsv
// Container: quay.io/biocontainers/bioconductor-absseq:1.64.0--r45hdfd78af_0
// Requires: ABSSeq
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct the ABSDataSet object without group information
//  * 2. [Core Analysis] Extract normalized counts
//  * 3. [Core Analysis] Perform variance stabilization using genAFold
//  * 4. [Core Analysis] Log2-transform the stabilized counts and run PCA using prcomp

nextflow.enable.dsl = 2

process BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA {
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
        
    # Load required library
    library(ABSSeq)
    
    # Read input file
    if (!file.exists("counts.tsv")) {
      stop("Error: 'counts.tsv' not found in the working directory.")
    }
    
    counts_matrix <- as.matrix(read.table("counts.tsv", header=TRUE, sep="\t", row.names=1, check.names=FALSE))
    
    # Ensure counts are numeric/integer
    storage.mode(counts_matrix) <- "integer"
    
    # 1. Construct the ABSDataSet object without group information
    obj <- ABSDataSet(counts=counts_matrix)
    
    # Define condition factor (as one group for variance stabilization)
    cond <- as.factor(rep("hex", ncol(counts_matrix)))
    
    # 2. Extract normalized counts
    cda <- counts(obj, T)
    
    # 3. Perform variance stabilization using genAFold
    sds <- genAFold(cda, cond)
    
    # 4. Log2-transform the stabilized counts and run PCA using prcomp
    ldat <- log2(sds[[4]])
    PCA <- prcomp(t(ldat), scale = F)
    percentVar <- round(100*PCA\$sdev^2/sum(PCA\$sdev^2),1)
    pc1=PCA\$x[,1]
    pc2=PCA\$x[,2]
    
    # Write outputs
    # Save stabilized counts (4th element of sds contains expression level adjusted counts)
    write.csv(sds[[4]], "variance_stabilized_counts.csv", row.names=TRUE)
    
    # Save PCA coordinates
    pca_df <- data.frame(Sample = colnames(ldat), PC1 = pc1, PC2 = pc2)
    write.csv(pca_df, "pca_coordinates.csv", row.names=FALSE)
    
    # Save percent variance
    var_df <- data.frame(PC = paste0("PC", seq_along(percentVar)), PercentVariance = percentVar)
    write.csv(var_df, "pca_variance.csv", row.names=FALSE)
    
    # Save PCA object as RDS
    saveRDS(PCA, "pca_object.rds")
    
    # Save PCA plot as PDF
    pdf("pca_plot.pdf")
    plot(pc1, pc2, main="PCA of Variance Stabilized Counts",
         pch=16, col="black",
         xlab=paste0("PC1 (", percentVar[1], "%)"),
         ylab=paste0("PC2 (", percentVar[2], "%)"), cex=1.2)
    text(pc1, pc2, labels=colnames(ldat), pos=3, cex=0.8)
    dev.off()

    writeLines(c(
        '"BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA":',
        paste0('    ABSSeq: ', as.character(packageVersion('ABSSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variance_stabilization_and_pca.csv versions.yml
    """
}

workflow BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.tsv ] ]

    main:
    BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA(ch_input)

    emit:
    tables   = BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA.out.tables
    plots    = BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA.out.plots
    objects  = BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA.out.objects
    versions = BIOC_ABSSEQ_VARIANCE_STABILIZATION_AND_PCA.out.versions
}
