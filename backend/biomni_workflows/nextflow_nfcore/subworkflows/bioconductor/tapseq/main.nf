#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TAPseq — target_gene_selection
// Select and assess a panel of cell-type marker genes from single-cell RNA-seq data.
// Input: bone_marrow_genex
// Container: quay.io/biocontainers/bioconductor-tapseq:1.22.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, TAPseq
// Visualizations: UMAP plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load single-cell data
//  * 2. [Core Analysis] Select target genes using lasso regularization (cross-validation or specifying target count)
//  * 3. [Visualization & Output] Assess target gene panels using UMAP plots

nextflow.enable.dsl = 2

process BIOC_TAPSEQ_TARGET_GENE_SELECTION {
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
    .bm_deps <- c("TAPseq", "Seurat")
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
    library(TAPseq)
    library(Seurat)
    
    # 1. Load single-cell data from the declared user input file
    # The pipeline expects 'bone_marrow_genex' as an RDS file in the working directory.
    if (file.exists("bone_marrow_genex")) {
      bone_marrow_genex <- readRDS("bone_marrow_genex")
    } else if (file.exists("bone_marrow_genex.rds")) {
      bone_marrow_genex <- readRDS("bone_marrow_genex.rds")
    } else {
      stop("Required input file 'bone_marrow_genex' (Seurat object in RDS format) not found in the working directory.")
    }
    
    # Transcript counts (inspecting first 10 genes and 10 cells)
    counts_subset <- GetAssayData(bone_marrow_genex, layer = "counts", assay = "RNA")[1:10, 1:10]
    print("Subset of transcript counts:")
    print(counts_subset)
    
    # Number of cells per cell type
    cell_type_counts <- table(Idents(bone_marrow_genex))
    print("Number of cells per cell type:")
    print(cell_type_counts)
    write.csv(as.data.frame(cell_type_counts), file = "cell_type_distribution.csv", row.names = FALSE)
    
    # 2. Select target genes using lasso regularization (cross-validation)
    print("Selecting target genes using 10-fold cross-validation...")
    target_genes_cv <- selectTargetGenes(bone_marrow_genex)
    print("First few cross-validation selected target genes:")
    print(head(target_genes_cv))
    print(paste("Total CV selected genes:", length(target_genes_cv)))
    
    # Save CV selected target genes
    write.table(target_genes_cv, file = "target_genes_cv.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    # Identify approximately 100 target genes that can be used to identify cell populations
    print("Selecting approximately 100 target genes...")
    target_genes_100 <- selectTargetGenes(bone_marrow_genex, targets = 100)
    print(paste("Total target genes selected (target ~100):", length(target_genes_100)))
    
    # Save 100 selected target genes
    write.table(target_genes_100, file = "target_genes_100.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    # 3. Assess target gene panels using UMAP plots
    print("Generating UMAP plots to assess target gene panels...")
    pdf("target_genes_umap_plots.pdf", width = 10, height = 5)
    p <- plotTargetGenes(bone_marrow_genex, target_genes = target_genes_100)
    print(p)
    dev.off()
    
    print("Workflow completed successfully. Outputs saved: 'cell_type_distribution.csv', 'target_genes_cv.txt', 'target_genes_100.txt', and 'target_genes_umap_plots.pdf'.")

    writeLines(c(
        '"BIOC_TAPSEQ_TARGET_GENE_SELECTION":',
        paste0('    TAPseq: ', as.character(packageVersion('TAPseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_target_gene_selection.csv versions.yml
    """
}

workflow BIOC_TAPSEQ_TARGET_GENE_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bone_marrow_genex ] ]

    main:
    BIOC_TAPSEQ_TARGET_GENE_SELECTION(ch_input)

    emit:
    tables   = BIOC_TAPSEQ_TARGET_GENE_SELECTION.out.tables
    plots    = BIOC_TAPSEQ_TARGET_GENE_SELECTION.out.plots
    objects  = BIOC_TAPSEQ_TARGET_GENE_SELECTION.out.objects
    versions = BIOC_TAPSEQ_TARGET_GENE_SELECTION.out.versions
}
