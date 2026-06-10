#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SNPRelate — pca_and_ld_pruning
// Perform LD-based SNP pruning followed by Principal Component Analysis (PCA) and SNP correlation analysis.
// Input: genofile
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// Requires: SNPRelate, gdsfmt
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform LD-based SNP pruning using snpgdsLDpruning
//  * 2. [Core Analysis] Extract pruned SNP IDs
//  * 3. [Core Analysis] Run PCA using snpgdsPCA
//  * 4. [Core Analysis] Calculate variance proportions
//  * 5. [Core Analysis] Compute SNP correlations with eigenvectors using snpgdsPCACorr

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_PCA_AND_LD_PRUNING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("SNPRelate", "gdsfmt")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(gdsfmt)
    library(SNPRelate)
    
    # Open the input GDS file from the working directory
    # The pipeline expects "genofile.gds" to be present in the working directory
    genofile <- snpgdsOpen("genofile.gds")
    
    # 1. Perform LD-based SNP pruning using snpgdsLDpruning
    snpset <- snpgdsLDpruning(genofile, ld.threshold=0.2)
    
    # 2. Extract pruned SNP IDs
    snpset.id <- unlist(unname(snpset))
    
    # 3. Run PCA using snpgdsPCA
    pca <- snpgdsPCA(genofile, snp.id=snpset.id, num.thread=2)
    
    # 4. Calculate variance proportions
    pc.percent <- pca\$varprop*100
    head(round(pc.percent, 2))
    
    # 5. Compute SNP correlations with eigenvectors using snpgdsPCACorr
    chr <- read.gdsn(index.gdsn(genofile, "snp.chromosome"))
    CORR <- snpgdsPCACorr(pca, genofile, eig.which=1:4)
    
    # --- WRITE OUTPUTS ---
    
    # Save pruned SNP IDs
    writeLines(as.character(snpset.id), "pruned_snp_ids.txt")
    
    # Save PCA eigenvectors
    pca_df <- data.frame(
      sample.id = pca\$sample.id,
      pca\$eigenvect,
      stringsAsFactors = FALSE
    )
    colnames(pca_df)[2:ncol(pca_df)] <- paste0("EV", 1:(ncol(pca_df)-1))
    write.csv(pca_df, "pca_eigenvectors.csv", row.names = FALSE)
    
    # Save PC variance proportions
    var_df <- data.frame(
      PC = paste0("PC", seq_along(pc.percent)),
      VarianceProportion = pc.percent
    )
    write.csv(var_df, "pca_variance_proportions.csv", row.names = FALSE)
    
    # Save SNP correlations object
    saveRDS(CORR, "snp_correlations.rds")
    
    # Generate and save diagnostic plots
    pdf("pca_and_correlation_plots.pdf", width = 8, height = 8)
    
    # Plot 1: PCA EV1 vs EV2
    plot(pca\$eigenvect[,2], pca\$eigenvect[,1], 
         xlab = "Eigenvector 2", ylab = "Eigenvector 1",
         main = "Principal Component Analysis (PCA)")
    
    # Plot 2: SNP Correlations for PC1 and PC2
    savepar <- par(mfrow=c(2,1), mai=c(0.45, 0.55, 0.1, 0.25))
    for (i in 1:2) {
        plot(abs(CORR\$snpcorr[i,]), ylim=c(0,1), xlab="", ylab=paste("PC", i),
             col=chr, pch="+")
    }
    par(savepar)
    
    dev.off()
    
    # Close the GDS file
    snpgdsClose(genofile)

    writeLines(c(
        '"BIOC_SNPRELATE_PCA_AND_LD_PRUNING":',
        paste0('    SNPRelate: ', as.character(packageVersion('SNPRelate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_and_ld_pruning.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_PCA_AND_LD_PRUNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genofile ] ]

    main:
    BIOC_SNPRELATE_PCA_AND_LD_PRUNING(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_PCA_AND_LD_PRUNING.out.tables
    plots    = BIOC_SNPRELATE_PCA_AND_LD_PRUNING.out.plots
    objects  = BIOC_SNPRELATE_PCA_AND_LD_PRUNING.out.objects
    versions = BIOC_SNPRELATE_PCA_AND_LD_PRUNING.out.versions
}
