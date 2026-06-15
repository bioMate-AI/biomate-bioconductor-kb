#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scran — gene_correlation_analysis
// Identify significant pairwise and gene-level correlations among highly variable genes (HVGs) while blocking on uninteresting batch effects.
// Input: sce.ready
// Container: quay.io/biocontainers/bioconductor-scran:1.38.0--r45ha27e39d_0
// R packages: SingleCellExperiment, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scran
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select top highly variable genes of interest
//  * 2. [Core Analysis] Compute pairwise correlations using correlatePairs()
//  * 3. [Core Analysis] Compute pairwise correlations blocking on batch/donor effects using correlatePairs(..., block=...)
//  * 4. [Visualization & Output] Summarize pairwise correlations into gene-level statistics using correlateGenes()

nextflow.enable.dsl = 2

process BIOC_SCRAN_GENE_CORRELATION_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "scran", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(scran)
    
    # 1. Read the input SingleCellExperiment object
    if (!file.exists("sce.ready")) {
      stop("Input file 'sce.ready' not found in the working directory.")
    }
    sce.ready <- readRDS("sce.ready")
    
    # 2. Select top highly variable genes of interest (top 200)
    of.interest <- order(rowData(sce.ready)\$residuals, decreasing=TRUE)[1:200]
    
    # 3. Compute pairwise correlations using correlatePairs()
    set.seed(100)
    cor.pairs <- correlatePairs(sce.ready, subset.row=of.interest)
    
    # 4. Compute pairwise correlations blocking on batch/donor effects
    if ("donor" %in% colnames(colData(sce.ready))) {
      set.seed(100)
      cor.pairs2 <- correlatePairs(sce.ready, subset.row=of.interest, block=sce.ready\$donor)
    } else {
      warning("Could not block on 'sce.ready\$donor'. Attempting to block on 'sce.ready\$sample' or skipping blocking.")
      if ("sample" %in% colnames(colData(sce.ready))) {
        set.seed(100)
        cor.pairs2 <- correlatePairs(sce.ready, subset.row=of.interest, block=sce.ready\$sample)
      } else {
        cor.pairs2 <- NULL
      }
    }
    
    # 5. Summarize pairwise correlations into gene-level statistics using correlateGenes()
    cor.genes <- correlateGenes(cor.pairs)
    
    # 6. Write outputs to files
    write.csv(as.data.frame(cor.pairs), "cor_pairs.csv", row.names=FALSE)
    saveRDS(cor.pairs, "cor_pairs.rds")
    
    if (!is.null(cor.pairs2)) {
      write.csv(as.data.frame(cor.pairs2), "cor_pairs_blocked.csv", row.names=FALSE)
      saveRDS(cor.pairs2, "cor_pairs_blocked.rds")
    }
    
    write.csv(as.data.frame(cor.genes), "cor_genes.csv", row.names=FALSE)
    saveRDS(cor.genes, "cor_genes.rds")
    
    message("Workflow completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_SCRAN_GENE_CORRELATION_ANALYSIS":',
        paste0('    scran: ', as.character(packageVersion('scran')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_SCRAN_GENE_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.ready ] ]

    main:
    BIOC_SCRAN_GENE_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCRAN_GENE_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_SCRAN_GENE_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_SCRAN_GENE_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_SCRAN_GENE_CORRELATION_ANALYSIS.out.versions
}
