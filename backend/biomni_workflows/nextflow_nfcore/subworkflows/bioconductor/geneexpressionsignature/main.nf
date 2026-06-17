#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneExpressionSignature — gene_expression_signature_pipeline
// Perform rank-based gene expression signature analysis to compute pairwise distances between biological states using GSEA and PGSEA algorithms.
// Input: counts.csv, coldata.csv
// Container: 1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GeneExpressionSignature
// Visualizations: heatmap (ComplexHeatmap)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE {
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
    .bm_deps <- c("GeneExpressionSignature", "Biobase")
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
    library(GeneExpressionSignature)
    library(Biobase)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    message("Stage 1: Loading and preprocessing input data...")
    
    # Read expression matrix (counts.csv holds normalized probe/gene expression values)
    counts <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    } else {
      rownames(counts) <- counts[, 1]
      counts <- counts[, -1, drop = FALSE]
    }
    expression_matrix <- as.matrix(counts)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Align counts and coldata
    common_samples <- intersect(coldata\$sample, colnames(expression_matrix))
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    expression_matrix <- expression_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # ==========================================
    # --- Data Ranking (getRLs) ---
    # ==========================================
    message("Stage 2: Generating ranked lists of genes...")
    
    # Identify control samples to compute relative rankings
    control_indices <- which(coldata\$condition %in% c("control", "Control", "untreated", "Untreated", "mock", "Mock", "WT", "wt"))
    if (length(control_indices) == 0) {
      # Fallback: use the first unique condition as control
      control_cond <- coldata\$condition[1]
      control_indices <- which(coldata\$condition == control_cond)
    }
    
    # Generate ranked lists using getRLs or fallback to direct ranking
    if (length(control_indices) > 0 && length(control_indices) < ncol(expression_matrix)) {
      control_mat <- expression_matrix[, control_indices, drop = FALSE]
      treatment_mat <- expression_matrix[, -control_indices, drop = FALSE]
      treatment_coldata <- coldata[-control_indices, , drop = FALSE]
      
      control_profile <- as.matrix(rowMeans(control_mat))
      
      ranked_list <- tryCatch({
        getRLs(control_profile, as.matrix(treatment_mat))
      }, error = function(e) {
        warning("getRLs failed, falling back to direct column-wise ranking: ", e\$message)
        apply(treatment_mat, 2, function(x) rank(-x))
      })
    } else {
      # Fallback if no valid control/treatment split is possible
      warning("No distinct control/treatment split possible. Ranking all samples relative to global mean.")
      global_mean <- as.matrix(rowMeans(expression_matrix))
      ranked_list <- tryCatch({
        getRLs(global_mean, expression_matrix)
      }, error = function(e) {
        apply(expression_matrix, 2, function(x) rank(-x))
      })
      treatment_coldata <- coldata
    }
    
    # Construct ExpressionSet for downstream analysis
    pheno_df <- data.frame(state = treatment_coldata\$condition)
    rownames(pheno_df) <- colnames(ranked_list)
    pheno_data <- AnnotatedDataFrame(pheno_df)
    eset <- ExpressionSet(assayData = as.matrix(ranked_list), phenoData = pheno_data)
    
    # ==========================================
    # --- Rank Merging ---
    # ==========================================
    message("Stage 3: Merging ranked lists by biological state...")
    
    # Merge multiple ranked lists belonging to the same biological state
    MergingSet <- RankMerging(eset, "Spearman", weighted = TRUE)
    
    # ==========================================
    # --- Similarity Measuring (GSEA & PGSEA) ---
    # ==========================================
    message("Stage 4: Measuring signature similarity...")
    
    # Dynamically determine signature length based on dataset size
    num_genes <- nrow(eset)
    sig_length <- max(10, min(250, floor(num_genes / 4)))
    message(paste("Using signature length:", sig_length))
    
    # Compute similarity distance matrix using GSEA
    ds_gsea <- ScoreGSEA(MergingSet, sig_length, "avg")
    
    # Compute similarity distance matrix using PGSEA
    ds_pgsea <- ScorePGSEA(MergingSet, sig_length, "avg")
    
    # Compute similarity distance matrix using the unified SignatureDistance function
    ds_sigdist <- SignatureDistance(
      eset,
      SignatureLength = sig_length,
      MergingDistance = "Spearman",
      ScoringMethod = "GSEA",
      ScoringDistance = "avg",
      weighted = TRUE
    )
    
    # ==========================================
    # --- Export Results and Visualization ---
    # ==========================================
    message("Stage 5: Exporting results and generating plots...")
    
    # Save distance matrices to CSV
    write.csv(as.matrix(ds_gsea), "gsea_distance_matrix.csv", row.names = TRUE)
    write.csv(as.matrix(ds_pgsea), "pgsea_distance_matrix.csv", row.names = TRUE)
    write.csv(as.matrix(ds_sigdist), "signature_distance_matrix.csv", row.names = TRUE)
    
    # Generate diagnostic plots
    pdf("distance_analysis_plots.pdf", width = 12, height = 10)
    par(mfrow = c(2, 2))
    
    # Heatmap of GSEA distances
    if (nrow(ds_gsea) > 1) {
      heatmap(as.matrix(ds_gsea), main = "GSEA Distance Heatmap", symm = TRUE, col = heat.colors(256))
      
      # Hierarchical clustering of GSEA distances
      hc_gsea <- hclust(as.dist(ds_gsea))
      plot(hc_gsea, main = "Hclust (GSEA Distance)", xlab = "Biological States", sub = "")
    } else {
      plot(1, type = "n", axes = FALSE, main = "GSEA Heatmap (Insufficient States)")
      plot(1, type = "n", axes = FALSE, main = "GSEA Hclust (Insufficient States)")
    }
    
    # Heatmap of PGSEA distances
    if (nrow(ds_pgsea) > 1) {
      heatmap(as.matrix(ds_pgsea), main = "PGSEA Distance Heatmap", symm = TRUE, col = terrain.colors(256))
      
      # Hierarchical clustering of PGSEA distances
      hc_pgsea <- hclust(as.dist(ds_pgsea))
      plot(hc_pgsea, main = "Hclust (PGSEA Distance)", xlab = "Biological States", sub = "")
    } else {
      plot(1, type = "n", axes = FALSE, main = "PGSEA Heatmap (Insufficient States)")
      plot(1, type = "n", axes = FALSE, main = "PGSEA Hclust (Insufficient States)")
    }
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE":',
        paste0('    GeneExpressionSignature: ', as.character(packageVersion('GeneExpressionSignature')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_expression_signature_pipeline.csv versions.yml
    """
}

workflow BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE.out.tables
    plots    = BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE.out.plots
    objects  = BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE.out.objects
    versions = BIOC_GENEEXPRESSIONSIGNATURE_GENE_EXPRESSION_SIGNATURE_PIPELINE.out.versions
}
