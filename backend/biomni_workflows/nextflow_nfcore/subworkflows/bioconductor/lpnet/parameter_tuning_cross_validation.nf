#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lpNet — parameter_tuning_cross_validation
// Find the optimal penalty parameter lambda using cross-validation (LOOCV or k-fold) to minimize mean squared error.
// Input: expression_matrix.csv, perturbation_design.csv
// Container: quay.io/biocontainers/bioconductor-lpnet:2.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: lpNet
// Visualizations: heatmap, network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define active and inactive state distribution parameters
//  * 2. [Core Analysis] Calculate the range of candidate lambda values using calcRangeLambda
//  * 3. [Core Analysis] Perform LOOCV or K-fold CV over the lambda range using loocv or kfoldCV
//  * 4. [Core Analysis] Select the best lambda minimizing MSE
//  * 5. [Core Analysis] Compute the final consensus adjacency matrix using getSampleAdjaMAD

nextflow.enable.dsl = 2

process BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION {
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
    .bm_deps <- c("lpNet")
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
        library(lpNet)
        
        # ==========================================
        # 1. Read User Input Files
        # ==========================================
        if (!file.exists("expression_matrix.csv") || !file.exists("perturbation_design.csv")) {
          stop("Required input files 'expression_matrix.csv' and/or 'perturbation_design.csv' are missing.")
        }
        
        # Read expression matrix (rows = genes, cols = experiments)
        obs_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        obs <- as.matrix(obs_df)
        
        # Read perturbation design matrix
        pert_df <- read.csv("perturbation_design.csv", row.names = 1, check.names = FALSE)
        pert <- as.matrix(pert_df)
        
        # Align dimensions if necessary (ensuring rows = genes, cols = experiments)
        if (nrow(pert) != nrow(obs) || ncol(pert) != ncol(obs)) {
          if (ncol(pert) == nrow(obs) && nrow(pert) == ncol(obs)) {
            pert <- t(pert)
          } else {
            stop("Dimensions of expression_matrix and perturbation_design do not match.")
          }
        }
        
        n <- nrow(obs) # number of genes
        K <- ncol(obs) # number of perturbation experiments
        
        # Convert perturbation matrix to vector 'b' (0 if gene inactivated, 1 otherwise)
        # Flattening column-by-column matches the experiment-by-experiment layout
        b <- as.vector(pert)
        
        # ==========================================
        # 2. Define Parameters & State Distributions
        # ==========================================
        delta <- apply(obs, 1, mean)
        delta_type <- "perGene"
        
        active_mu <- 1.1
        inactive_mu <- 0.9
        active_sd <- inactive_sd <- 0.01
        mu_type <- "single"
        
        times <- 5 # number of times the removed observation is sampled
        annot_node <- seq(1, n) # annotation of the nodes
        
        # ==========================================
        # 3. Calculate Range of Candidate Lambdas
        # ==========================================
        lambda <- calcRangeLambda(obs, delta, delta_type)
        
        # ==========================================
        # 4. Perform LOOCV over Lambda Range
        # ==========================================
        MSE <- Inf
        bestLambda <- NULL
        edges_all <- NULL
        
        for (lamd in lambda) {
          loocv_res <- loocv(kfold = NULL, times, obs, delta, lambda = lamd, 
                             b, n, K, T_ = NULL, annot = getEdgeAnnot(n), 
                             annot_node, active_mu, active_sd, 
                             inactive_mu, inactive_sd, mu_type, 
                             delta_type)
          if (loocv_res\$MSE < MSE) {
            MSE <- loocv_res\$MSE
            edges_all <- loocv_res\$edges_all
            bestLambda <- lamd
          }
        }
        
        # ==========================================
        # 5. Compute Final Consensus Adjacency Matrix
        # ==========================================
        adja_bestLambda <- getSampleAdjaMAD(edges_all, n, annot_node)
        
        # Assign gene names to the resulting adjacency matrix
        gene_names <- rownames(obs)
        if (!is.null(gene_names)) {
          rownames(adja_bestLambda) <- gene_names
          colnames(adja_bestLambda) <- gene_names
        }
        
        # ==========================================
        # 6. Write Output Files
        # ==========================================
        # Save the best lambda and corresponding MSE
        summary_df <- data.frame(
          Metric = c("Best_Lambda", "Minimum_MSE"),
          Value = c(bestLambda, MSE)
        )
        write.csv(summary_df, "cv_parameter_summary.csv", row.names = FALSE)
        
        # Save the final adjacency matrix
        write.csv(adja_bestLambda, "optimal_adjacency_matrix.csv", row.names = TRUE)
        
        # Save the raw edges and CV results as an RDS object for downstream analysis
        saveRDS(list(
          best_lambda = bestLambda,
          min_mse = MSE,
          edges_all = edges_all,
          adjacency_matrix = adja_bestLambda
        ), "loocv_tuning_results.rds")
        
        # Generate and save a heatmap of the reconstructed network
        pdf("reconstructed_network_heatmap.pdf", width = 7, height = 7)
        if (!is.null(gene_names)) {
          heatmap(adja_bestLambda, Rowv = NA, Colv = NA, scale = "none",
                  col = colorRampPalette(c("white", "red"))(25),
                  main = paste("Inferred Network (Lambda =", round(bestLambda, 3), ")"))
        } else {
          heatmap(adja_bestLambda, Rowv = NA, Colv = NA, scale = "none",
                  col = colorRampPalette(c("white", "red"))(25),
                  main = paste("Inferred Network (Lambda =", round(bestLambda, 3), ")"))
        }
        dev.off()

    writeLines(c(
        '"BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION":',
        paste0('    lpNet: ', as.character(packageVersion('lpNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parameter_tuning_cross_validation.csv versions.yml
    """
}

workflow BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, perturbation_design.csv ] ]

    main:
    BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION.out.tables
    plots    = BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION.out.plots
    objects  = BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION.out.objects
    versions = BIOC_LPNET_PARAMETER_TUNING_CROSS_VALIDATION.out.versions
}
