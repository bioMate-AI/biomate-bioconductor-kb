#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ANF — single_view_spectral_clustering
// Perform spectral clustering on a single feature matrix by constructing an affinity matrix from distances.
// Input: feature1
// Container: quay.io/biocontainers/bioconductor-anf:1.32.0--r45hdfd78af_0
// R packages: ANF, ExperimentHub, igraph, MASS
// Bioconductor: 3.20 | R: 4.4
// Requires: ANF
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the user input file 'feature1' from the working
//  * 2. [Input & Preparation] Compute the distance matrix and convert it to a matrix
//  * 3. [Input & Preparation] Construct the affinity matrix using affinity_matrix
//  * 4. [Input & Preparation] Perform spectral clustering using spectral_clustering
//  * 5. [Input & Preparation] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ANF", "ExperimentHub", "igraph", "MASS")
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
    library(ANF)
    
    # --- Read the user input file 'feature1' from the working ---
    # We check for common formats like CSV, TSV, or TXT.
    if (file.exists("feature1.csv")) {
      feature1 <- as.matrix(read.csv("feature1.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("feature1.tsv")) {
      feature1 <- as.matrix(read.delim("feature1.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("feature1.txt")) {
      feature1 <- as.matrix(read.table("feature1.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Input file 'feature1' (e.g., feature1.csv, feature1.tsv, or feature1.txt) not found in the working directory.")
    }
    
    # --- Compute the distance matrix and convert it to a matrix ---
    d = dist(feature1)
    d = as.matrix(d)
    
    # --- Construct the affinity matrix using affinity_matrix ---
    A1 = affinity_matrix(d, 10)
    
    # --- Perform spectral clustering using spectral_clustering ---
    labels = spectral_clustering(A1, 2)
    
    # --- Write named output files for the meaningful results ---
    # Save the cluster labels
    output_labels <- data.frame(
      ID = rownames(feature1),
      Cluster = labels,
      stringsAsFactors = FALSE
    )
    if (is.null(rownames(feature1))) {
      output_labels\$ID <- paste0("Object_", seq_len(nrow(feature1)))
    }
    write.csv(output_labels, "spectral_clustering_labels.csv", row.names = FALSE)
    
    # Save the affinity matrix
    write.csv(A1, "affinity_matrix.csv", row.names = TRUE)
    saveRDS(A1, "affinity_matrix.rds")
    
    # Generate and save a heatmap of the affinity matrix
    pdf("affinity_heatmap.pdf", width = 8, height = 8)
    heatmap(A1, 
            Rowv = NA, 
            Colv = NA, 
            col = heat.colors(256), 
            scale = "none",
            main = "Affinity Matrix Heatmap")
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved: 'spectral_clustering_labels.csv', 'affinity_matrix.csv', 'affinity_matrix.rds', and 'affinity_heatmap.pdf'.\n")

    writeLines(c(
        '"BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING":',
        paste0('    ANF: ', as.character(packageVersion('ANF')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_view_spectral_clustering.csv versions.yml
    """
}

workflow BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ feature1 ] ]

    main:
    BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING.out.tables
    plots    = BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING.out.plots
    objects  = BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING.out.objects
    versions = BIOC_ANF_SINGLE_VIEW_SPECTRAL_CLUSTERING.out.versions
}
