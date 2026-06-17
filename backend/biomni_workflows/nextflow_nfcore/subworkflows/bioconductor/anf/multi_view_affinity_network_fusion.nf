#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ANF — multi_view_affinity_network_fusion
// Fuse multiple affinity matrices representing different views (e.g., multi-omic data) and perform spectral clustering on the fused matrix.
// Input: Wall, project_ids
// Container: quay.io/biocontainers/bioconductor-anf:1.32.0--r45hdfd78af_0
// R packages: ANF
// Bioconductor: 3.20 | R: 4.4
// Requires: ANF
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fuse multiple affinity matrices using ANF
//  * 2. [Core Analysis] Perform spectral clustering on the fused affinity matrix
//  * 3. [Core Analysis] Evaluate the clustering results against true classes

nextflow.enable.dsl = 2

process BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION {
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
    .bm_deps <- c("ANF")
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
    library(ANF)
    
    # Define input file paths
    wall_path <- "Wall.rds"
    project_ids_path <- "project_ids.rds"
    
    # Verify and read input files
    if (!file.exists(wall_path)) {
      stop(paste("Error: Input file", wall_path, "not found in the working directory."))
    }
    if (!file.exists(project_ids_path)) {
      stop(paste("Error: Input file", project_ids_path, "not found in the working directory."))
    }
    
    Wall <- readRDS(wall_path)
    project_ids <- readRDS(project_ids_path)
    
    # Validate that the required structure exists in Wall
    if (!is.list(Wall)) {
      stop("Error: The input 'Wall' object must be a list of affinity matrices.")
    }
    
    # --- Fuse multiple affinity matrices using ANF ---
    fused.mat <- ANF(Wall = Wall)
    
    # --- Perform spectral clustering on the fused affinity matrix ---
    labels <- spectral_clustering(A = fused.mat, k = 2)
    
    # --- Evaluate the clustering results against true classes ---
    res <- eval_clu(true_class = project_ids[rownames(fused.mat)], w = fused.mat)
    
    # Save meaningful results to output files
    # Save the fused affinity matrix
    saveRDS(fused.mat, "fused_matrix.rds")
    write.csv(as.matrix(fused.mat), "fused_matrix.csv", row.names = TRUE)
    
    # Save the spectral clustering labels
    labels_df <- data.frame(
      SampleID = rownames(fused.mat),
      Cluster = labels,
      stringsAsFactors = FALSE
    )
    write.csv(labels_df, "spectral_clustering_labels.csv", row.names = FALSE)
    
    # Save the evaluation results
    saveRDS(res, "evaluation_results.rds")
    
    # Write a text summary of the evaluation results
    sink("evaluation_summary.txt")
    cat("=== Clustering Evaluation Summary ===\n\n")
    print(res)
    sink()
    
    message("Pipeline completed successfully. Outputs saved to 'fused_matrix.rds', 'fused_matrix.csv', 'spectral_clustering_labels.csv', 'evaluation_results.rds', and 'evaluation_summary.txt'.")

    writeLines(c(
        '"BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION":',
        paste0('    ANF: ', as.character(packageVersion('ANF')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_view_affinity_network_fusion.csv versions.yml
    """
}

workflow BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Wall, project_ids ] ]

    main:
    BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION(ch_input)

    emit:
    tables   = BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION.out.tables
    plots    = BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION.out.plots
    objects  = BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION.out.objects
    versions = BIOC_ANF_MULTI_VIEW_AFFINITY_NETWORK_FUSION.out.versions
}
