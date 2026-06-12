#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: partCNV — part_cnv_standard
// Identify locally aneuploid cells using the standard partCNV EM algorithm.
// Input: scRNA_seq_counts.rds, cytogenetics_info.txt
// Container: quay.io/biocontainers/bioconductor-partcnv:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Seurat, ggplot2, partCNV
// Visualizations: bar plot, UMAP/t-SNE plot, UMAP plot
// QC: count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve genomic coordinates for the cytogenetics feature
//  * 2. [Core Analysis] Subset and filter the count matrix
//  * 3. [Core Analysis] Run the EM algorithm for cell classification

nextflow.enable.dsl = 2

process BIOC_PARTCNV_PART_CNV_STANDARD {
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
    .bm_deps <- c("partCNV", "Seurat", "ggplot2")
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
    
    # Load required packages
    library(partCNV)
    
    # -----------------------------------------------------------------------------
    # 1. Input Validation and Loading
    # -----------------------------------------------------------------------------
    
    if (!file.exists("scRNA_seq_counts.rds")) {
      stop("Error: 'scRNA_seq_counts.rds' not found in the working directory.")
    }
    
    if (!file.exists("cytogenetics_info.txt")) {
      stop("Error: 'cytogenetics_info.txt' not found in the working directory.")
    }
    
    # Read the normalized scRNA-seq count matrix
    counts_matrix <- readRDS("scRNA_seq_counts.rds")
    
    # Read the cytogenetics prior information
    # Expected format: a headered table with columns: feature, proportion, type
    # Example:
    # feature   proportion  type
    # chr20(q11.1-q13.1)    0.40    del
    cyto_info <- read.table("cytogenetics_info.txt", header = TRUE, stringsAsFactors = FALSE)
    
    if (!all(c("feature", "proportion", "type") %in% colnames(cyto_info))) {
      stop("Error: 'cytogenetics_info.txt' must contain 'feature', 'proportion', and 'type' columns.")
    }
    
    cyto_feature_val <- cyto_info\$feature[1]
    cyto_p_val <- as.numeric(cyto_info\$proportion[1])
    cyto_type_val <- cyto_info\$type[1]
    
    # -----------------------------------------------------------------------------
    # 2. Run partCNV Standard Workflow
    # -----------------------------------------------------------------------------
    
    # Step 1: Retrieve genomic coordinates for the cytogenetics feature
    res <- GetCytoLocation(cyto_feature = cyto_feature_val)
    
    # Step 2: Subset and filter the count matrix
    GEout <- GetExprCountCyto(
      cytoloc_output = res,
      Counts = as.matrix(counts_matrix),
      normalization = TRUE,
      qt_cutoff = 0.99
    )
    
    # Step 3: Run the EM algorithm for cell classification
    pcout <- partCNV(
      int_counts = GEout\$ProcessedCount,
      cyto_type = cyto_type_val,
      cyto_p = cyto_p_val
    )
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save the raw classification vector as an RDS object
    saveRDS(pcout, "partCNV_results.rds")
    
    # Save the classification results as a CSV table
    results_df <- data.frame(
      Cell_ID = names(pcout),
      partCNV_label = pcout,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "partCNV_cell_labels.csv", row.names = FALSE)
    
    # Generate a basic summary plot
    pdf("partCNV_classification_summary.pdf", width = 6, height = 6)
    barplot(
      table(pcout),
      main = paste("partCNV Cell Classification\nFeature:", cyto_feature_val),
      xlab = "Classification (0 = diploid, 1 = aneuploid)",
      ylab = "Number of Cells",
      col = c("lightblue", "salmon")
    )
    dev.off()
    
    # Optional: Generate Seurat UMAP visualization if Seurat and ggplot2 are available
    if (requireNamespace("Seurat", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)) {
      tryCatch({
        library(Seurat)
        library(ggplot2)
        
        # Create Seurat object and run standard dimension reduction
        sim_seurat <- CreateSeuratObject(counts = counts_matrix)
        sim_seurat <- NormalizeData(sim_seurat, normalization.method = "LogNormalize", scale.factor = 10000)
        sim_seurat <- FindVariableFeatures(sim_seurat, selection.method = "vst", nfeatures = min(2000, nrow(counts_matrix)))
        all_genes <- rownames(sim_seurat)
        sim_seurat <- ScaleData(sim_seurat, features = all_genes)
        sim_seurat <- RunPCA(sim_seurat, features = VariableFeatures(object = sim_seurat), verbose = FALSE)
        sim_seurat <- RunUMAP(sim_seurat, dims = 1:min(10, ncol(sim_seurat) - 1), verbose = FALSE)
        
        # Align cell labels
        common_cells <- intersect(names(pcout), colnames(sim_seurat))
        if (length(common_cells) > 0) {
          sim_seurat <- subset(sim_seurat, cells = common_cells)
          pcout_sub <- pcout[common_cells]
          
          sim_seurat <- AddMetaData(
            object = sim_seurat,
            metadata = pcout_sub,
            col.name = "partCNV_label"
          )
          
          sim_seurat\$partCNV_label <- factor(
            sim_seurat\$partCNV_label,
            levels = c(1, 0),
            labels = c("aneuploid", "diploid")
          )
          
          p1 <- sum(pcout_sub == 1) / length(pcout_sub)
          
          pdf("partCNV_umap.pdf", width = 7, height = 6)
          print(
            DimPlot(sim_seurat, reduction = "umap", group.by = "partCNV_label") +
            ggtitle(paste0("partCNV (", signif(p1, 2) * 100, "%)"))
          )
          dev.off()
        }
      }, error = function(e) {
        warning("Seurat visualization skipped or failed: ", e\$message)
      })
    }
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_PARTCNV_PART_CNV_STANDARD":',
        paste0('    partCNV: ', as.character(packageVersion('partCNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_part_cnv_standard.csv versions.yml
    """
}

workflow BIOC_PARTCNV_PART_CNV_STANDARD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ scRNA_seq_counts.rds, cytogenetics_info.txt ] ]

    main:
    BIOC_PARTCNV_PART_CNV_STANDARD(ch_input)

    emit:
    tables   = BIOC_PARTCNV_PART_CNV_STANDARD.out.tables
    plots    = BIOC_PARTCNV_PART_CNV_STANDARD.out.plots
    objects  = BIOC_PARTCNV_PART_CNV_STANDARD.out.objects
    versions = BIOC_PARTCNV_PART_CNV_STANDARD.out.versions
}
