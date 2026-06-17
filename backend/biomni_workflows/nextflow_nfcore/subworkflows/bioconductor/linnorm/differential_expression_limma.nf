#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Linnorm — differential_expression_limma
// Perform differential expression analysis on count data using the integrated Linnorm-limma pipeline.
// Input: LIHC, IslamData
// Container: quay.io/biocontainers/bioconductor-linnorm:2.34.0--r45ha27e39d_0
// R packages: Linnorm
// Bioconductor: 3.20 | R: 4.4
// Requires: Linnorm
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the experimental design matrix
//  * 2. [Core Analysis] Run the Linnorm-limma pipeline to identify differentially expressed genes
//  * 3. [Core Analysis] Extract and filter significant genes
//  * 4. [Visualization & Output] Generate a volcano plot

nextflow.enable.dsl = 2

process BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA {
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
    .bm_deps <- c("Linnorm")
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
        
    # Load required libraries
    library(Linnorm)
    
    # Helper function to read input files robustly from the working directory
    read_input <- function(file_name) {
      if (file.exists(paste0(file_name, ".rds"))) {
        return(readRDS(paste0(file_name, ".rds")))
      } else if (file.exists(file_name)) {
        res <- try(readRDS(file_name), silent=TRUE)
        if (!inherits(res, "try-error")) return(res)
        return(as.matrix(read.table(file_name, header=TRUE, row.names=1, sep="\t", check.names=FALSE)))
      } else if (file.exists(paste0(file_name, ".txt"))) {
        return(as.matrix(read.table(paste0(file_name, ".txt"), header=TRUE, row.names=1, sep="\t", check.names=FALSE)))
      } else if (file.exists(paste0(file_name, ".csv"))) {
        return(as.matrix(read.csv(paste0(file_name, ".csv"), header=TRUE, row.names=1, check.names=FALSE)))
      } else {
        stop(paste("Required input file not found:", file_name))
      }
    }
    
    # ==========================================
    # PART 1: LIHC Dataset Analysis
    # ==========================================
    
    # Read LIHC count matrix
    datamatrix <- read_input("LIHC")
    
    # 1. Define the experimental design matrix dynamically based on input dimensions
    n_samples <- ncol(datamatrix)
    n_group1 <- floor(n_samples / 2)
    n_group2 <- n_samples - n_group1
    design <- c(rep(1, n_group1), rep(2, n_group2))
    design <- model.matrix(~ 0+factor(design))
    colnames(design) <- c("group1", "group2")
    rownames(design) <- colnames(datamatrix)
    
    # 2. Run the Linnorm-limma pipeline to identify differentially expressed genes
    # Basic run
    DEG_Results_Basic <- Linnorm.limma(datamatrix, design)
    
    # Advanced run to obtain both DEG results and the transformed matrix
    BothResults <- Linnorm.limma(datamatrix, design, output="Both")
    
    # Separate results into two matrices
    DEG_Results <- BothResults\$DEResults
    TransformedMatrix <- BothResults\$Linnorm
    
    # Save the full DEG results and transformed matrix
    write.table(DEG_Results, "DEG_Results.txt", quote=FALSE, sep="\t",
                col.names=TRUE, row.names=TRUE)
    write.table(TransformedMatrix, "TransformedMatrix.txt", quote=FALSE, sep="\t",
                col.names=TRUE, row.names=TRUE)
    
    # 3. Extract and filter significant genes
    Genes10 <- DEG_Results[order(DEG_Results[,"adj.P.Val"]),][1:10,]
    write.table(Genes10, "Top10_Significant_Genes.txt", quote=FALSE, sep="\t",
                col.names=TRUE, row.names=TRUE)
    
    SignificantGenes <- DEG_Results[DEG_Results[,5] <= 0.05, 1]
    
    # 4. Generate a volcano plot
    pdf("volcano_plot.pdf", width=6, height=6)
    plot(x=DEG_Results[,1], y=DEG_Results[,5], col=ifelse(DEG_Results[,1] %in%
    SignificantGenes, "red", "green"), log="y", ylim = 
    rev(range(DEG_Results[,5])), main="Volcano Plot", 
    xlab="log2 Fold Change", ylab="q values", cex = 0.5)
    dev.off()
    
    
    # ==========================================
    # PART 2: Single-Cell RNA-seq Analysis (IslamData)
    # ==========================================
    
    # Read IslamData count matrix
    IslamData <- read_input("IslamData")
    
    # 1. Define the experimental design matrix dynamically for single-cell data
    n_samples_sc <- ncol(IslamData)
    n_group1_sc <- floor(n_samples_sc / 2)
    n_group2_sc <- n_samples_sc - n_group1_sc
    design_sc <- c(rep(1, n_group1_sc), rep(2, n_group2_sc))
    design_sc <- model.matrix(~ 0+factor(design_sc))
    colnames(design_sc) <- c("group1", "group2")
    rownames(design_sc) <- colnames(IslamData)
    
    # 2. Run the Linnorm-limma pipeline with filtering for single-cell data
    scRNAseqResults <- Linnorm.limma(IslamData, design_sc, Filter=TRUE)
    
    # Save single-cell DEG results
    write.table(scRNAseqResults, "scRNAseq_DEG_Results.txt", quote=FALSE, sep="\t",
                col.names=TRUE, row.names=TRUE)

    writeLines(c(
        '"BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA":',
        paste0('    Linnorm: ', as.character(packageVersion('Linnorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_limma.csv versions.yml
    """
}

workflow BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ LIHC, IslamData ] ]

    main:
    BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA(ch_input)

    emit:
    tables   = BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA.out.tables
    plots    = BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA.out.plots
    objects  = BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA.out.objects
    versions = BIOC_LINNORM_DIFFERENTIAL_EXPRESSION_LIMMA.out.versions
}
