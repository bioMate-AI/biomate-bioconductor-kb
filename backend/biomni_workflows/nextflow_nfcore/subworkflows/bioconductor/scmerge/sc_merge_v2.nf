#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMerge — sc_merge_v2
// Integrate single-cell RNA-seq batches using the graph-clustering and pseudobulk-based scMerge2 algorithm.
// Input: example_sce, segList_ensemblGeneID
// Container: quay.io/biocontainers/bioconductor-scmerge:1.26.0--r45hdfd78af_0
// R packages: DelayedMatrixStats, SingleCellExperiment, batchelor, ggplot2, scMerge, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: DelayedMatrixStats, SingleCellExperiment, batchelor, ggplot2, scMerge, scater
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run unsupervised or semi-supervised scMerge2
//  * 2. [Core Analysis] Assign the adjusted matrix back to the SingleCellExperiment object
//  * 3. [Core Analysis] Perform memory-efficient subsetted adjustment using getAdjustedMat

nextflow.enable.dsl = 2

process BIOC_SCMERGE_SC_MERGE_V2 {
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
    .bm_deps <- c("DelayedMatrixStats", "SingleCellExperiment", "batchelor", "ggplot2", "scMerge", "scater")
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
    library(scMerge)
    library(scater)
    library(batchelor)
    library(DelayedMatrixStats)
    library(ggplot2)
    
    # ------------------------------------------------------------------------------
    # 1. Load User Input Files
    # ------------------------------------------------------------------------------
    # The pipeline reads exactly these files from the working directory
    example_sce <- readRDS("example_sce.rds")
    segList_ensemblGeneID <- readRDS("segList_ensemblGeneID.rds")
    
    # Ensure batch is a factor for downstream level-based looping
    if (!is.factor(example_sce\$batch)) {
      example_sce\$batch <- as.factor(example_sce\$batch)
    }
    
    # Set up PDF for plotting PCA results at each stage
    pdf("scMerge2_integration_plots.pdf", width = 10, height = 8)
    
    # Plot raw PCA for comparison
    example_sce <- scater::runPCA(example_sce, exprs_values = "logcounts")
    p_raw <- scater::plotPCA(example_sce, colour_by = "cellTypes", shape_by = "batch") +
      ggplot2::labs(title = "Raw logcounts PCA (Before Integration)")
    print(p_raw)
    
    # ------------------------------------------------------------------------------
    # 2. Unsupervised scMerge2
    # ------------------------------------------------------------------------------
    scMerge2_res <- scMerge2(exprsMat = logcounts(example_sce),
                             batch = example_sce\$batch,
                             ctl = segList_ensemblGeneID\$mouse\$mouse_scSEG,
                             verbose = FALSE)
    
    assay(example_sce, "scMerge2") <- scMerge2_res\$newY
    
    # Plot Unsupervised scMerge2 PCA
    example_sce <- scater::runPCA(example_sce, exprs_values = "scMerge2")
    p_unsupervised <- scater::plotPCA(example_sce, colour_by = "cellTypes", shape_by = "batch") +
      ggplot2::labs(title = "Unsupervised scMerge2 PCA")
    print(p_unsupervised)
    
    # ------------------------------------------------------------------------------
    # 3. Semi-supervised scMerge2
    # ------------------------------------------------------------------------------
    scMerge2_res <- scMerge2(exprsMat = logcounts(example_sce),
                             batch = example_sce\$batch,
                             cellTypes = example_sce\$cellTypes,
                             ctl = segList_ensemblGeneID\$mouse\$mouse_scSEG,
                             verbose = FALSE)
    
    assay(example_sce, "scMerge2") <- scMerge2_res\$newY
    
    # Plot Semi-supervised scMerge2 PCA
    example_sce <- scater::runPCA(example_sce, exprs_values = "scMerge2")
    p_semisupervised <- scater::plotPCA(example_sce, colour_by = "cellTypes", shape_by = "batch") +
      ggplot2::labs(title = "Semi-supervised scMerge2 PCA")
    print(p_semisupervised)
    
    # ------------------------------------------------------------------------------
    # 4. Memory-efficient Subsetted Adjustment using getAdjustedMat
    # ------------------------------------------------------------------------------
    scMerge2_res <- scMerge2(exprsMat = logcounts(example_sce),
                             batch = example_sce\$batch,
                             ctl = segList_ensemblGeneID\$mouse\$mouse_scSEG,
                             verbose = FALSE,
                             return_matrix = FALSE)
    
    cosineNorm_mat <- batchelor::cosineNorm(logcounts(example_sce))
    adjusted_means <- DelayedMatrixStats::rowMeans2(cosineNorm_mat)
    
    newY <- list()
    for (i in levels(example_sce\$batch)) {
        newY[[i]] <- getAdjustedMat(cosineNorm_mat[, example_sce\$batch == i], 
                                    scMerge2_res\$fullalpha,
                                    ctl = segList_ensemblGeneID\$mouse\$mouse_scSEG,
                                    ruvK = 20,
                                    adjusted_means = adjusted_means)
    }
    newY <- do.call(cbind, newY)
    assay(example_sce, "scMerge2") <- newY[, colnames(example_sce)]
    
    # Plot Memory-efficient Subsetted Adjustment PCA
    example_sce <- scater::runPCA(example_sce, exprs_values = "scMerge2")
    p_subsetted <- scater::plotPCA(example_sce, colour_by = "cellTypes", shape_by = "batch") +
      ggplot2::labs(title = "Memory-efficient Subsetted scMerge2 PCA")
    print(p_subsetted)
    
    dev.off()
    
    # ------------------------------------------------------------------------------
    # 5. Save Outputs
    # ------------------------------------------------------------------------------
    # Save the integrated SingleCellExperiment object
    saveRDS(example_sce, "example_sce_scMerge2_integrated.rds")
    
    # Save the final normalized expression matrix
    write.csv(as.matrix(assay(example_sce, "scMerge2")), "scMerge2_normalized_expression.csv")

    writeLines(c(
        '"BIOC_SCMERGE_SC_MERGE_V2":',
        paste0('    scMerge: ', as.character(packageVersion('scMerge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_merge_v2.csv versions.yml
    """
}

workflow BIOC_SCMERGE_SC_MERGE_V2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sce, segList_ensemblGeneID ] ]

    main:
    BIOC_SCMERGE_SC_MERGE_V2(ch_input)

    emit:
    tables   = BIOC_SCMERGE_SC_MERGE_V2.out.tables
    plots    = BIOC_SCMERGE_SC_MERGE_V2.out.plots
    objects  = BIOC_SCMERGE_SC_MERGE_V2.out.objects
    versions = BIOC_SCMERGE_SC_MERGE_V2.out.versions
}
