#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scrapper — basic_sc_rna_seq_analysis
// Perform an end-to-end single-cell RNA-seq analysis workflow including QC, normalization, PCA, clustering, and marker detection using a single wrapper function.
// Input: sce.z
// Container: quay.io/biocontainers/bioconductor-scrapper:1.4.0--r45ha27e39d_0
// R packages: SingleCellExperiment, BiocStyle, DelayedArray, knitr, scater, scrapper, scRNAseq
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scater, scrapper
// Visualizations: ordination plot, t-SNE plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify mitochondrial genes
//  * 2. [Core Analysis] Run end-to-end analysis with analyze.se()
//  * 3. [Visualization & Output] Visualize results with plotReducedDim()
//  * 4. [Core Analysis] Inspect marker genes with previewMarkers()

nextflow.enable.dsl = 2

process BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS {
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
    .bm_deps <- c("SingleCellExperiment", "BiocStyle", "DelayedArray", "knitr", "scater", "scrapper", "scRNAseq")
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
    library(scrapper)
    library(scater)
    
    # 1. Read the input SingleCellExperiment object from the working directory
    sce.z <- readRDS("sce.z")
    
    # 2. Identify mitochondrial genes
    is.mito <- grep("^mt-", rownames(sce.z))
    
    # 3. Run end-to-end analysis with analyze.se()
    results <- analyze.se(
        sce.z,
        rna.qc.subsets=list(Mito=is.mito),
        num.threads=2 # limit number of threads to keep R CMD check happy.
    )
    
    # Save the analyzed SingleCellExperiment object (which contains the results)
    saveRDS(results\$x, "analyzed_sce.rds")
    
    # 4. Visualize results with plotReducedDim() and save to PDF
    pdf("tsne_plot.pdf", width=8, height=6)
    p <- plotReducedDim(results\$x, "TSNE", colour_by="graph.cluster")
    print(p)
    dev.off()
    
    # 5. Inspect marker genes with previewMarkers() and save to CSV
    markers_preview <- previewMarkers(results\$markers\$rna[[1]], order.by="auc.median")
    write.csv(as.data.frame(markers_preview), "marker_genes.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS":',
        paste0('    scrapper: ', as.character(packageVersion('scrapper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic_sc_rna_seq_analysis.csv versions.yml
    """
}

workflow BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.z ] ]

    main:
    BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.tables
    plots    = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.plots
    objects  = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.objects
    versions = BIOC_SCRAPPER_BASIC_SC_RNA_SEQ_ANALYSIS.out.versions
}
