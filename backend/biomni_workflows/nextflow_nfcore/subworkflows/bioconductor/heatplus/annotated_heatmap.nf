#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Heatplus — annotated_heatmap
// Generate a heatmap with column (sample) annotations and colored dendrogram clusters.
// Input: exprs_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-heatplus:3.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Heatplus
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load expression data and sample metadata from user input
//  * 2. [Visualization & Output] Generate annotated heatmap object using annHeatmap (ann1)
//  * 3. [Visualization & Output] Specify dendrogram cutting height and cluster labels
//  * 4. [Visualization & Output] Save meaningful outputs (RDS objects and CSV tables)

nextflow.enable.dsl = 2

process BIOC_HEATPLUS_ANNOTATED_HEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Biobase", "Heatplus")
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
        library(Biobase)
        library(Heatplus)
        
        # --- Load expression data and sample metadata from user input ---
        exprs_matrix <- as.matrix(read.csv("exprs_matrix.csv", row.names = 1, check.names = FALSE))
        sample_metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
        
        # Align the expression matrix columns with sample metadata rows
        common_samples <- intersect(colnames(exprs_matrix), rownames(sample_metadata))
        if (length(common_samples) == 0) {
          stop("Error: No common samples found between exprs_matrix.csv columns and sample_metadata.csv rows.")
        }
        exprs_matrix <- exprs_matrix[, common_samples, drop = FALSE]
        sample_metadata <- sample_metadata[common_samples, , drop = FALSE]
        
        # Construct the ExpressionSet objects to match the documented code's data structure
        exdat <- ExpressionSet(
          assayData = exprs_matrix,
          phenoData = AnnotatedDataFrame(sample_metadata)
        )
        
        # For exdat2, select the top 50 most variable features to represent a filtered subset
        feature_vars <- apply(exprs(exdat), 1, var)
        top_features <- names(sort(feature_vars, decreasing = TRUE))[1:min(50, length(feature_vars))]
        exdat2 <- exdat[top_features, ]
        
        # --- Generate annotated heatmap object using annHeatmap (ann1) ---
        ann1 <- annHeatmap(exprs(exdat), ann=pData(exdat))
        
        # Save ann1 plot to PDF
        pdf("heatmap_ann1.pdf", width = 10, height = 8)
        plot(ann1)
        dev.off()
        
        # --- Specify dendrogram cutting height and cluster labels ---
        # Calculate column dendrogram to determine dynamic cut heights
        hc_col <- hclust(dist(t(exprs(exdat2))))
        max_height <- max(hc_col\$height)
        cuth2 <- max_height * 0.5
        
        ann2 <- annHeatmap(exprs(exdat2), ann=pData(exdat2), cluster=list(cuth=cuth2))
        
        # Save ann2 plot to PDF
        pdf("heatmap_ann2.pdf", width = 10, height = 8)
        plot(ann2)
        dev.off()
        
        # Generate ann3 with custom cluster labels matching the actual number of clusters
        cuth3 <- max_height * 0.75
        k3 <- length(unique(cutree(hc_col, h=cuth3)))
        labels3 <- paste0("Cluster", 1:k3)
        
        ann3 <- annHeatmap(exprs(exdat2), ann=pData(exdat2), cluster=list(cuth=cuth3, label=labels3))
        
        # Save ann3 plot to PDF
        pdf("heatmap_ann3.pdf", width = 10, height = 8)
        plot(ann3)
        dev.off()
        
        # --- Save meaningful outputs (RDS objects and CSV tables) ---
        saveRDS(ann1, "ann1.rds")
        saveRDS(ann2, "ann2.rds")
        saveRDS(ann3, "ann3.rds")
        
        # Extract and save column cluster assignments if available
        if (!is.null(ann2\$cluster\$Col\$grp)) {
          clusters_df <- data.frame(
            Sample = names(ann2\$cluster\$Col\$grp),
            Cluster_ann2 = ann2\$cluster\$Col\$grp,
            Cluster_ann3 = if (!is.null(ann3\$cluster\$Col\$grp)) ann3\$cluster\$Col\$grp else NA
          )
          write.csv(clusters_df, "column_clusters.csv", row.names = FALSE)
        }

    writeLines(c(
        '"BIOC_HEATPLUS_ANNOTATED_HEATMAP":',
        paste0('    Heatplus: ', as.character(packageVersion('Heatplus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotated_heatmap.csv versions.yml
    """
}

workflow BIOC_HEATPLUS_ANNOTATED_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_HEATPLUS_ANNOTATED_HEATMAP(ch_input)

    emit:
    tables   = BIOC_HEATPLUS_ANNOTATED_HEATMAP.out.tables
    plots    = BIOC_HEATPLUS_ANNOTATED_HEATMAP.out.plots
    objects  = BIOC_HEATPLUS_ANNOTATED_HEATMAP.out.objects
    versions = BIOC_HEATPLUS_ANNOTATED_HEATMAP.out.versions
}
