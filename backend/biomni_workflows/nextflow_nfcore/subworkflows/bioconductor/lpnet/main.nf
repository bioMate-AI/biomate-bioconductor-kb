#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lpNet — steady_state_network_inference
// Infer a signaling network from steady-state perturbation data using integer linear programming.
// Input: expression_matrix.csv, perturbation_design.csv
// Container: quay.io/biocontainers/bioconductor-lpnet:2.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: lpNet
// Visualizations: image plot, heatmap, network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define network size and perturbation vector
//  * 2. [Core Analysis] Compute delta thresholds
//  * 3. [Core Analysis] Generate edge annotations using getEdgeAnnot
//  * 4. [Core Analysis] Run ILP network reconstruction using doILP
//  * 5. [Core Analysis] Convert the LP result to an adjacency matrix using getAdja

nextflow.enable.dsl = 2

process BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE {
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
    .bm_deps <- c("lpNet")
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
    
    # Load required library
    library(lpNet)
    
    # Read user input files
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: expression_matrix.csv not found in the working directory.")
    }
    if (!file.exists("perturbation_design.csv")) {
      stop("Error: perturbation_design.csv not found in the working directory.")
    }
    
    obs_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    obs <- as.matrix(obs_df)
    
    b_df <- read.csv("perturbation_design.csv", row.names = 1, check.names = FALSE)
    
    # Validate dimensions
    if (nrow(b_df) != nrow(obs) || ncol(b_df) != ncol(obs)) {
      stop("Error: Dimensions of expression_matrix.csv and perturbation_design.csv do not match.")
    }
    
    # 1. Define network size and perturbation vector
    n <- nrow(obs) # number of genes
    K <- ncol(obs) # number of perturbation experiments
    b <- as.vector(as.matrix(b_df))
    
    # 2. Compute delta thresholds
    delta <- apply(obs, 1, mean, na.rm = TRUE)
    delta_type <- "perGene"
    
    # 3 & 4. Generate edge annotations using getEdgeAnnot and run ILP network reconstruction using doILP
    res1 <- doILP(obs, delta, lambda=1, b, n, K, T_=NULL,
                  annot=getEdgeAnnot(n), delta_type)
    
    # 5. Convert the LP result to an adjacency matrix using getAdja
    adja1 <- getAdja(res1, n)
    
    # Assign gene names to the adjacency matrix for clarity
    gene_names <- rownames(obs_df)
    if (!is.null(gene_names)) {
      rownames(adja1) <- gene_names
      colnames(adja1) <- gene_names
    }
    
    # Write outputs
    write.csv(adja1, "inferred_adjacency_matrix.csv", row.names = TRUE)
    saveRDS(res1, "ilp_result.rds")
    
    # Generate a PDF plot of the adjacency matrix
    pdf("network_adjacency_heatmap.pdf", width = 6, height = 6)
    if (!is.null(gene_names)) {
      image(t(adja1[nrow(adja1):1, , drop = FALSE]), col = c("white", "blue"),
            axes = FALSE, main = "Inferred Network Adjacency Matrix")
      axis(1, at = seq(0, 1, length.out = ncol(adja1)), labels = colnames(adja1), las = 2)
      axis(2, at = seq(0, 1, length.out = nrow(adja1)), labels = rev(rownames(adja1)), las = 2)
    } else {
      image(t(adja1[nrow(adja1):1, , drop = FALSE]), col = c("white", "blue"),
            axes = FALSE, main = "Inferred Network Adjacency Matrix")
    }
    dev.off()

    writeLines(c(
        '"BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE":',
        paste0('    lpNet: ', as.character(packageVersion('lpNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_steady_state_network_inference.csv versions.yml
    """
}

workflow BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, perturbation_design.csv ] ]

    main:
    BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE.out.tables
    plots    = BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE.out.plots
    objects  = BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE.out.objects
    versions = BIOC_LPNET_STEADY_STATE_NETWORK_INFERENCE.out.versions
}
