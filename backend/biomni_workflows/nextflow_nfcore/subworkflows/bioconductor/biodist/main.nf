#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bioDist — mutual_information_and_kl_divergence_distance
// Calculate mutual information and Kullback-Leibler divergence distances between samples in an expression dataset.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-biodist:1.82.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: bioDist
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read the user input file
//  * 2. [Core Analysis] Transpose the expression matrix to compute distances
//  * 3. [Core Analysis] Compute mutual information distance using MIdist
//  * 4. [Core Analysis] Compute distance from independence using mutualInfo
//  * 5. [Core Analysis] Compute Kullback-Leibler divergence using binning
//  * 6. [Core Analysis] Compute Kullback-Leibler divergence using density
//  * 7. [Core Analysis] Save results to output files

nextflow.enable.dsl = 2

process BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE {
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
    .bm_deps <- c("bioDist")
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
    library("bioDist")
    
    # --- Read the user input file ---
    # The input file 'expression_matrix.csv' has genes as rows and samples as columns.
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    
    expr_mat <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # --- Transpose the expression matrix to compute distances ---
    # In bioDist, distance functions compute pairwise distances between the rows of the input.
    # Transposing ensures we compute distances between samples.
    exData = t(expr_mat)
    
    # --- Compute mutual information distance using MIdist ---
    message("Computing mutual information distance (MIdist)...")
    s1 = MIdist(exData)
    s2 = as.matrix(s1)
    dim(s2)
    
    # --- Compute distance from independence using mutualInfo ---
    message("Computing mutual information (mutualInfo)...")
    r1 = mutualInfo(exData)
    r1_matrix = as.matrix(r1)
    
    # --- Compute Kullback-Leibler divergence using binning ---
    message("Computing Kullback-Leibler distance via binning (KLdist.matrix)...")
    kl1 = KLdist.matrix(exData)
    kl1_matrix = as.matrix(kl1)
    
    # --- Compute Kullback-Leibler divergence using density ---
    message("Computing Kullback-Leibler distance via density estimation (KLD.matrix)...")
    kl2 = KLD.matrix(exData, method="density", supp=range(exData))
    kl2_matrix = as.matrix(kl2)
    
    # --- Save results to output files ---
    message("Saving results...")
    
    # Save CSV tables
    write.csv(s2, "mutual_info_distance_matrix.csv", row.names = TRUE)
    write.csv(r1_matrix, "mutual_info_independence_matrix.csv", row.names = TRUE)
    write.csv(kl1_matrix, "kl_distance_binning_matrix.csv", row.names = TRUE)
    write.csv(kl2_matrix, "kl_distance_density_matrix.csv", row.names = TRUE)
    
    # Save RDS objects for downstream R analysis
    saveRDS(s1, "mutual_info_distance.rds")
    saveRDS(r1, "mutual_info_independence.rds")
    saveRDS(kl1, "kl_distance_binning.rds")
    saveRDS(kl2, "kl_distance_density.rds")
    
    # Generate a PDF plot visualizing the distance matrices
    pdf("distance_plots.pdf", width = 10, height = 10)
    par(mfrow = c(2, 2))
    
    if (nrow(s2) > 1) {
      # Heatmap of Mutual Information Distance
      image(1:nrow(s2), 1:ncol(s2), s2, main = "Mutual Info Distance (MIdist)", 
            xlab = "Samples", ylab = "Samples", col = heat.colors(12))
      
      # Heatmap of Mutual Info Independence
      image(1:nrow(r1_matrix), 1:ncol(r1_matrix), r1_matrix, main = "Mutual Info (mutualInfo)", 
            xlab = "Samples", ylab = "Samples", col = heat.colors(12))
      
      # Heatmap of KL Divergence (Binning)
      image(1:nrow(kl1_matrix), 1:ncol(kl1_matrix), kl1_matrix, main = "KL Dist (Binning)", 
            xlab = "Samples", ylab = "Samples", col = terrain.colors(12))
      
      # Heatmap of KL Divergence (Density)
      image(1:nrow(kl2_matrix), 1:ncol(kl2_matrix), kl2_matrix, main = "KL Dist (Density)", 
            xlab = "Samples", ylab = "Samples", col = terrain.colors(12))
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "Insufficient samples to plot heatmaps", cex = 1.5)
    }
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to current directory.")

    writeLines(c(
        '"BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE":',
        paste0('    bioDist: ', as.character(packageVersion('bioDist')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mutual_information_and_kl_divergence_distance.csv versions.yml
    """
}

workflow BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE(ch_input)

    emit:
    tables   = BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE.out.tables
    plots    = BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE.out.plots
    objects  = BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE.out.objects
    versions = BIOC_BIODIST_MUTUAL_INFORMATION_AND_KL_DIVERGENCE_DISTANCE.out.versions
}
