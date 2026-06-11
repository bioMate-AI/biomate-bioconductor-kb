#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: yarn — rna_seq_preprocessing_and_normalization
// Preprocess, quality-control, filter, and normalize multi-tissue RNA-Seq expression data.
// Input: ExpressionSet object
// Container: quay.io/biocontainers/bioconductor-yarn:1.36.0--r45hdfd78af_0
// R packages: Biobase, RColorBrewer, yarn
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, RColorBrewer, yarn
// Visualizations: density plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Check for sample mis-annotation using checkMisAnnotation
//  * 2. [Core Analysis] Identify sub-groups/tissues to merge using checkTissuesToMerge
//  * 3. [Core Analysis] Filter lowly expressed genes using filterLowGenes
//  * 4. [Core Analysis] Filter specific gene groups (e.g., sex chromosomes) using filterGenes
//  * 5. [Visualization & Output] Visualize raw expression density using plotDensity
//  * 6. [Core Analysis] Normalize expression data in a tissue-aware manner using normalizeTissueAware
//  * 7. [Visualization & Output] Visualize normalized expression density using plotDensity
//  * 8. [Visualization & Output] Perform dimensionality reduction and quality control visualization using plotCMDS and plotHeatmap

nextflow.enable.dsl = 2

process BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION {
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
    .bm_deps <- c("Biobase", "RColorBrewer", "yarn")
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
        library(yarn)
        library(RColorBrewer)
        library(Biobase)
        
        # ==========================================
        # 1. Load User Input
        # ==========================================
        # The pipeline expects an ExpressionSet object saved as "expression_set.rds"
        # in the working directory.
        input_file <- "expression_set.rds"
        if (!file.exists(input_file)) {
          stop(paste("Error: Input file", input_file, "not found in the working directory."))
        }
        
        eset <- readRDS(input_file)
        
        # Extract generic column names to avoid hardcoding demo-specific names
        pheno_cols <- colnames(pData(eset))
        feat_cols <- colnames(fData(eset))
        
        if (length(pheno_cols) == 0) stop("Error: No phenotype columns found in the ExpressionSet.")
        if (length(feat_cols) == 0) stop("Error: No feature columns found in the ExpressionSet.")
        
        col_gender <- pheno_cols[1]
        col_tissue <- if (length(pheno_cols) >= 2) pheno_cols[2] else pheno_cols[1]
        col_subtissue <- if (length(pheno_cols) >= 3) pheno_cols[3] else col_tissue
        col_chrom <- feat_cols[1]
        
        # ==========================================
        # 2. Check Mis-annotation
        # ==========================================
        pdf("misannotation_check.pdf", width = 7, height = 7)
        checkMisAnnotation(eset, col_gender, controlGenes = "Y", legendPosition = "topleft")
        dev.off()
        
        # ==========================================
        # 3. Identify Sub-groups/Tissues to Merge
        # ==========================================
        pdf("tissues_to_merge_check.pdf", width = 7, height = 7)
        checkTissuesToMerge(eset, col_tissue, col_subtissue)
        dev.off()
        
        # ==========================================
        # 4. Filter Lowly Expressed Genes
        # ==========================================
        eset_filtered = filterLowGenes(eset, col_subtissue)
        
        # Print dimensions to standard output
        cat("Original dimensions:\n")
        print(dim(eset))
        cat("Filtered dimensions:\n")
        print(dim(eset_filtered))
        
        # ==========================================
        # 5. Filter Specific Gene Groups
        # ==========================================
        tmp = filterGenes(eset, labels = c("X", "Y", "MT"), featureName = col_chrom)
        saveRDS(tmp, "tmp_filtered_genes_excluded.rds")
        
        tmp = filterGenes(eset, labels = c("X", "Y", "MT"), featureName = col_chrom, keepOnly = TRUE)
        saveRDS(tmp, "tmp_filtered_genes_keepOnly.rds")
        
        # ==========================================
        # 6. Visualize Raw Expression Density
        # ==========================================
        pdf("density_raw.pdf", width = 7, height = 7)
        plotDensity(eset_filtered, col_subtissue, main = expression('log'[2]*' raw expression'))
        dev.off()
        
        # ==========================================
        # 7. Normalize Expression Data (Tissue-Aware)
        # ==========================================
        eset_filtered = normalizeTissueAware(eset_filtered, col_subtissue)
        saveRDS(eset_filtered, "eset_filtered_normalized.rds")
        
        # ==========================================
        # 8. Visualize Normalized Expression Density
        # ==========================================
        pdf("density_normalized.pdf", width = 7, height = 7)
        plotDensity(eset_filtered, col_subtissue, normalized = TRUE, main = "Normalized")
        dev.off()
        
        # ==========================================
        # 9. Dimensionality Reduction & QC Visualization
        # ==========================================
        # Classical Multi-Dimensional Scaling (CMDS)
        pdf("cmds_plot.pdf", width = 7, height = 7)
        res = plotCMDS(eset, pch = 21, bg = factor(pData(eset)[[col_subtissue]]))
        dev.off()
        saveRDS(res, "cmds_results.rds")
        
        # Density plot of filtered data
        filtData = filterLowGenes(eset, col_subtissue)
        pdf("density_filtered.pdf", width = 7, height = 7)
        plotDensity(filtData, groups = col_subtissue, legendPos = "topleft")
        dev.off()
        
        # Heatmap of the most variable genes
        tissues = pData(eset)[[col_subtissue]]
        heatmapColColors = brewer.pal(12, "Set3")[as.integer(factor(tissues))]
        heatmapCols = colorRampPalette(brewer.pal(9, "RdBu"))(50)
        
        pdf("heatmap.pdf", width = 10, height = 10)
        plotHeatmap(eset, normalized = FALSE, log = TRUE, trace = "none", n = 10,
                    col = heatmapCols, ColSideColors = heatmapColColors, cexRow = 0.25, cexCol = 0.25)
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION":',
        paste0('    yarn: ', as.character(packageVersion('yarn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_preprocessing_and_normalization.csv versions.yml
    """
}

workflow BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet object ] ]

    main:
    BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION.out.tables
    plots    = BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION.out.plots
    objects  = BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION.out.objects
    versions = BIOC_YARN_RNA_SEQ_PREPROCESSING_AND_NORMALIZATION.out.versions
}
