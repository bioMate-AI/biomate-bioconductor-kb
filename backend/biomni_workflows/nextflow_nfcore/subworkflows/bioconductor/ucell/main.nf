#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: UCell — matrix_and_precalculated_ranks
// Score gene signatures on a raw or normalized expression matrix, with the option to pre-calculate rankings to speed up iterative signature testing.
// Input: sample.matrix, exp.mat
// Container: quay.io/biocontainers/bioconductor-ucell:2.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Matrix, UCell, ggplot2, reshape2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define gene signatures as a list of character vectors
//  * 2. [Core Analysis] Score signatures directly on the expression matrix using ScoreSignatures_UCell
//  * 3. [Core Analysis] Pre-calculate and store gene rankings using StoreRankings_UCell
//  * 4. [Core Analysis] Score new or modified signatures rapidly using the pre-calculated rankings in ScoreSignatures_UCell

nextflow.enable.dsl = 2

process BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS {
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
    .bm_deps <- c("UCell", "Matrix", "BiocParallel", "reshape2", "ggplot2")
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
    library(UCell)
    library(Matrix)
    library(BiocParallel)
    library(reshape2)
    library(ggplot2)
    
    # Read user input files from the working directory
    # Assuming these are stored as RDS files containing sparse matrices
    sample.matrix <- readRDS("sample.matrix")
    exp.mat <- readRDS("exp.mat")
    
    # 1. Define gene signatures as a list of character vectors
    gene.sets <- list(
      Tcell_signature = c("CD2", "CD3E", "CD3D"),
      Myeloid_signature = c("SPI1", "FCER1G", "CSF1R")
    )
    
    signatures <- list(
      Tcell = c("CD3D", "CD3E", "CD3G", "CD2", "TRAC"),
      Myeloid = c("CD14", "LYZ", "CSF1R", "FCER1G", "SPI1", "LCK-"),
      NK = c("KLRD1", "NCR1", "NKG7", "CD3D-", "CD3E-"),
      Plasma_cell = c("MZB1", "DERL3", "CD19-")
    )
    
    new.signatures <- list(
      Mast.cell = c("TPSAB1", "TPSB2", "CPA3", "MS4A2"),
      Lymphoid = c("LCK")
    )
    
    # 2. Score signatures directly on the expression matrix using ScoreSignatures_UCell
    scores <- ScoreSignatures_UCell(sample.matrix, features=gene.sets)
    
    # 3. Pre-calculate and store gene rankings using StoreRankings_UCell
    ranks <- StoreRankings_UCell(exp.mat)
    
    # 4. Score new or modified signatures rapidly using the pre-calculated rankings
    u.scores.2 <- ScoreSignatures_UCell(features=signatures, precalc.ranks = ranks)
    u.scores.3 <- ScoreSignatures_UCell(features=new.signatures, precalc.ranks = ranks)
    
    # 5. Multi-core processing run
    BPPARAM <- BiocParallel::MulticoreParam(workers=1)
    u.scores <- ScoreSignatures_UCell(exp.mat,features=signatures, BPPARAM=BPPARAM)
    
    # Write meaningful results to output files
    write.csv(as.data.frame(scores), "scores_direct.csv", row.names = TRUE)
    saveRDS(ranks, "precalculated_ranks.rds")
    write.csv(as.data.frame(u.scores.2), "scores_precalc_signatures.csv", row.names = TRUE)
    write.csv(as.data.frame(u.scores.3), "scores_precalc_new_signatures.csv", row.names = TRUE)
    write.csv(as.data.frame(u.scores), "scores_parallel.csv", row.names = TRUE)
    
    # Generate diagnostic plots
    pdf("ucell_score_distributions.pdf", width = 12, height = 5)
    
    # Plot for u.scores.2
    melted2 <- reshape2::melt(u.scores.2)
    colnames(melted2) <- c("Cell", "Signature", "UCell_score")
    p2 <- ggplot(melted2, aes(x = Signature, y = UCell_score)) +
      geom_violin(aes(fill = Signature), scale = "width") +
      geom_boxplot(width = 0.1, outlier.size = 0) +
      theme_bw() +
      theme(axis.text.x = element_blank()) +
      ggtitle("UCell Scores: Standard Signatures (Pre-calculated Ranks)")
    
    # Plot for u.scores.3
    melted3 <- reshape2::melt(u.scores.3)
    colnames(melted3) <- c("Cell", "Signature", "UCell_score")
    p3 <- ggplot(melted3, aes(x = Signature, y = UCell_score)) +
      geom_violin(aes(fill = Signature), scale = "width") +
      geom_boxplot(width = 0.1, outlier.size = 0) +
      theme_bw() +
      theme(axis.text.x = element_blank()) +
      ggtitle("UCell Scores: New Signatures (Pre-calculated Ranks)")
    
    print(p2)
    print(p3)
    
    dev.off()

    writeLines(c(
        '"BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS":',
        paste0('    UCell: ', as.character(packageVersion('UCell')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_and_precalculated_ranks.csv versions.yml
    """
}

workflow BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.matrix, exp.mat ] ]

    main:
    BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS(ch_input)

    emit:
    tables   = BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS.out.tables
    plots    = BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS.out.plots
    objects  = BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS.out.objects
    versions = BIOC_UCELL_MATRIX_AND_PRECALCULATED_RANKS.out.versions
}
