#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: M3Drop — non_umi_m3drop_workflow
// Perform dropout-based feature selection, cell clustering, and marker gene identification for non-UMI single-cell RNA-seq data using the Michaelis-Menten model.
// Input: counts, labels
// Container: quay.io/biocontainers/bioconductor-m3drop:1.36.0--r45hdfd78af_0
// R packages: M3Drop, ROCR
// Bioconductor: 3.20 | R: 4.4
// Requires: M3Drop
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-quality cells based on minimum detected genes
//  * 2. [Core Analysis] Convert and normalize raw counts to a non-log-transformed expression matrix using M3DropConvertData
//  * 3. [Core Analysis] Perform feature selection using M3DropFeatureSelection
//  * 4. [Visualization & Output] Visualize selected features using M3DropExpressionHeatmap
//  * 5. [Visualization & Output] Cluster cells from the heatmap using M3DropGetHeatmapClusters
//  * 6. [Core Analysis] Identify marker genes for the clusters using M3DropGetMarkers

nextflow.enable.dsl = 2

process BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW {
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
    .bm_deps <- c("M3Drop", "ROCR")
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
        library(M3Drop)
        library(ROCR)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        
        # Find counts file in the working directory
        counts_files <- c("counts.rds", "counts.csv", "counts.tsv")
        counts_file <- counts_files[file.exists(counts_files)][1]
        if (is.na(counts_file)) {
          stop("No counts file found. Please provide counts.rds, counts.csv, or counts.tsv in the working directory.")
        }
        
        if (grepl("\\\\.rds\$", counts_file)) {
          counts <- readRDS(counts_file)
        } else if (grepl("\\\\.csv\$", counts_file)) {
          counts <- as.matrix(read.csv(counts_file, row.names=1, check.names=FALSE))
        } else {
          counts <- as.matrix(read.delim(counts_file, row.names=1, check.names=FALSE))
        }
        
        # Find labels file in the working directory
        labels_files <- c("labels.rds", "labels.csv", "labels.tsv", "labels.txt")
        labels_file <- labels_files[file.exists(labels_files)][1]
        if (is.na(labels_file)) {
          stop("No labels file found. Please provide labels.rds, labels.csv, labels.tsv, or labels.txt in the working directory.")
        }
        
        if (grepl("\\\\.rds\$", labels_file)) {
          labels <- readRDS(labels_file)
        } else if (grepl("\\\\.csv\$", labels_file)) {
          labels <- read.csv(labels_file, header=FALSE)[,1]
        } else if (grepl("\\\\.tsv\$", labels_file)) {
          labels <- read.delim(labels_file, header=FALSE)[,1]
        } else {
          labels <- readLines(labels_file)
        }
        
        # Ensure labels match the number of columns in counts
        if (length(labels) != ncol(counts)) {
          warning("Length of labels does not match number of columns in counts. Adjusting labels.")
          if (length(labels) > ncol(counts)) {
            labels <- labels[1:ncol(counts)]
          } else {
            labels <- c(labels, rep("Unknown", ncol(counts) - length(labels)))
          }
        }
        
        # ==========================================
        # 2. Execute Documented M3Drop Workflow
        # ==========================================
        
        # Filter low-quality cells based on minimum detected genes
        total_features <- colSums(counts >= 0)
        counts <- counts[,total_features >= 2000, drop=FALSE]
        labels <- labels[total_features >= 2000]
        
        # Convert and normalize raw counts to a non-log-transformed expression matrix
        norm <- M3DropConvertData(counts, is.counts=TRUE)
        
        # Perform feature selection using the Michaelis-Menten model
        M3Drop_genes <- M3DropFeatureSelection(norm, mt_method="fdr", mt_threshold=0.01)
        
        # Save selected features to CSV
        write.csv(M3Drop_genes, "M3Drop_selected_genes.csv", row.names=FALSE)
        
        # Check if any significant genes were found before proceeding
        if (nrow(M3Drop_genes) == 0) {
          stop("No significant genes found by M3DropFeatureSelection. Terminating pipeline.")
        }
        
        # Visualize selected features using M3DropExpressionHeatmap
        pdf("M3Drop_heatmap.pdf", width=10, height=10)
        heat_out <- M3DropExpressionHeatmap(M3Drop_genes\$Gene, norm, cell_labels = labels)
        dev.off()
        
        # Cluster cells from the heatmap (dynamically adjust k based on number of cells)
        k_clusters <- min(4, ncol(norm))
        cell_populations <- M3DropGetHeatmapClusters(heat_out, k=k_clusters, type="cell")
        
        # Save cell population assignments to CSV
        write.csv(data.frame(Cell=names(cell_populations), Cluster=cell_populations), 
                  "cell_populations.csv", row.names=FALSE)
        
        # Identify marker genes for the clusters
        marker_genes <- M3DropGetMarkers(norm, cell_populations)
        
        # Save marker genes to CSV
        write.csv(marker_genes, "marker_genes.csv", row.names=TRUE)
        
        # Display top markers for Group 4 and check for Cdx2 as in the vignette
        print("Top 20 marker genes for Group 4:")
        print(head(marker_genes[marker_genes\$Group==4,], 20))
        
        print("Checking for Cdx2 marker gene status:")
        tryCatch({
          print(marker_genes[rownames(marker_genes)=="Cdx2",])
        }, error = function(e) {
          message("Cdx2 gene not present in the dataset.")
        })
        
        message("M3Drop pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW":',
        paste0('    M3Drop: ', as.character(packageVersion('M3Drop')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_non_umi_m3drop_workflow.csv versions.yml
    """
}

workflow BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, labels ] ]

    main:
    BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW.out.tables
    plots    = BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW.out.plots
    objects  = BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW.out.objects
    versions = BIOC_M3DROP_NON_UMI_M3DROP_WORKFLOW.out.versions
}
