#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scds — doublet_annotation
// Annotate and score doublets in single-cell RNA-seq data using co-expression, binary classification, and hybrid approaches.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-scds:1.26.0--r45hdfd78af_0
// R packages: SingleCellExperiment, cowplot, devtools, rsvd, Rtsne, scater, scds
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scds
// Visualizations: box plot
// QC: doublet detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run co-expression based doublet scoring (cxds)
//  * 2. [Core Analysis] Run binary classification based doublet scoring (bcds)
//  * 3. [Core Analysis] Run the hybrid doublet scoring approach (cxds_bcds_hybrid)
//  * 4. [Core Analysis] Extract top gene pairs driving the co-expression doublet annotations

nextflow.enable.dsl = 2

process BIOC_SCDS_DOUBLET_ANNOTATION {
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
    .bm_deps <- c("SingleCellExperiment", "cowplot", "devtools", "rsvd", "Rtsne", "scater", "scds", "SummarizedExperiment")
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
    library(scds)
    library(SummarizedExperiment)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects a SingleCellExperiment object named 'sce' or 'sce.rds'
    # in the working directory containing raw counts in the "counts" assay.
    if (file.exists("sce")) {
      sce <- readRDS("sce")
    } else if (file.exists("sce.rds")) {
      sce <- readRDS("sce.rds")
    } else {
      stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    # Ensure the counts assay exists
    if (!"counts" %in% assayNames(sce)) {
      stop("Error: The input SingleCellExperiment object must contain a 'counts' assay.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1-3: Run Doublet Scoring (cxds, bcds, hybrid)
    # -----------------------------------------------------------------------------
    # Run co-expression based doublet scoring
    sce = cxds(sce,retRes = TRUE)
    
    # Run binary classification based doublet scoring
    sce = bcds(sce,retRes = TRUE,verb=TRUE)
    
    # Run the hybrid doublet scoring approach
    sce = cxds_bcds_hybrid(sce)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Extract Top Gene Pairs Driving Co-expression Doublet Annotations
    # -----------------------------------------------------------------------------
    scds =
    top3 = metadata(sce)\$cxds\$topPairs[1:3,]
    rs   = rownames(sce)
    hb   = rowData(sce)\$cxds_hvg_bool
    ho   = rowData(sce)\$cxds_hvg_ordr[hb]
    hgs  = rs[ho]
    
    # -----------------------------------------------------------------------------
    # Stage 5: Save Outputs and Visualizations
    # -----------------------------------------------------------------------------
    # Save the updated SingleCellExperiment object
    saveRDS(sce, file = "sce_doublets_annotated.rds")
    
    # Save the top gene pairs driving the co-expression doublet annotations
    top_pairs_df <- data.frame(
      Rank = 1:3,
      Gene1 = hgs[top3[, 1]],
      Gene2 = hgs[top3[, 2]]
    )
    write.csv(top_pairs_df, file = "top_doublet_gene_pairs.csv", row.names = FALSE)
    
    # Generate diagnostic plots of doublet scores
    pdf("doublet_scores_distribution.pdf", width = 12, height = 4)
    if ("doublet_true_labels" %in% colnames(colData(sce))) {
      par(mfcol = c(1, 3))
      boxplot(sce\$cxds_score   ~ sce\$doublet_true_labels, main = "cxds", xlab = "True Label", ylab = "Score")
      boxplot(sce\$bcds_score   ~ sce\$doublet_true_labels, main = "bcds", xlab = "True Label", ylab = "Score")
      boxplot(sce\$hybrid_score ~ sce\$doublet_true_labels, main = "hybrid", xlab = "True Label", ylab = "Score")
    } else {
      par(mfcol = c(1, 3))
      hist(sce\$cxds_score, main = "cxds_score", xlab = "Score", col = "skyblue")
      hist(sce\$bcds_score, main = "bcds_score", xlab = "Score", col = "salmon")
      hist(sce\$hybrid_score, main = "hybrid_score", xlab = "Score", col = "lightgreen")
    }
    dev.off()

    writeLines(c(
        '"BIOC_SCDS_DOUBLET_ANNOTATION":',
        paste0('    scds: ', as.character(packageVersion('scds')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_doublet_annotation.csv versions.yml
    """
}

workflow BIOC_SCDS_DOUBLET_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_SCDS_DOUBLET_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_SCDS_DOUBLET_ANNOTATION.out.tables
    plots    = BIOC_SCDS_DOUBLET_ANNOTATION.out.plots
    objects  = BIOC_SCDS_DOUBLET_ANNOTATION.out.objects
    versions = BIOC_SCDS_DOUBLET_ANNOTATION.out.versions
}
