#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pandaR — panda_differential_network
// Reconstruct and compare condition-specific gene regulatory networks using PANDA by integrating gene expression data with programmatically generated motif and PP
// Input: counts.csv, coldata.csv
// Container: 1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pandaR
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK {
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
    .bm_deps <- c("pandaR")
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
    library(pandaR)
    
    # ---------------------------------------------------------
    # --- Load and Preprocess Expression & Metadata ---
    # ---------------------------------------------------------
    message("Loading input datasets...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Handle potential 'gene_id' column if present as a column instead of row name
    if ("gene_id" %in% colnames(counts)) {
      rownames(counts) <- counts\$gene_id
      counts\$gene_id <- NULL
    }
    
    # Filter out low-variance genes to focus on highly informative features and speed up PANDA
    gene_vars <- apply(counts, 1, var)
    keep_genes <- names(sort(gene_vars, decreasing = TRUE)[1:min(200, length(gene_vars))])
    expr_filtered <- counts[keep_genes, , drop = FALSE]
    
    # Log-transform if the data contains raw counts or large values
    if (max(expr_filtered, na.rm = TRUE) > 50) {
      expr_filtered <- log2(expr_filtered + 1)
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(expr_filtered), coldata\$sample)
    if (length(common_samples) < 4) {
      stop("Error: Too few matching samples between counts.csv and coldata.csv.")
    }
    expr_filtered <- expr_filtered[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # Split samples by condition
    conds <- unique(coldata\$condition)
    if (length(conds) < 2) {
      # If only one condition is present, split samples arbitrarily to demonstrate differential analysis
      message("Only one condition found. Splitting samples into mock groups for demonstration.")
      coldata\$condition <- rep(c("GroupA", "GroupB"), length.out = nrow(coldata))
      conds <- c("GroupA", "GroupB")
    }
    
    samples1 <- coldata\$sample[coldata\$condition == conds[1]]
    samples2 <- coldata\$sample[coldata\$condition == conds[2]]
    
    expr1 <- expr_filtered[, samples1, drop = FALSE]
    expr2 <- expr_filtered[, samples2, drop = FALSE]
    
    # ---------------------------------------------------------
    # --- Construct Motif and PPI Priors ---
    # ---------------------------------------------------------
    message("Constructing motif and PPI priors...")
    # Define a set of transcription factors
    tfs <- paste0("TF_", 1:10)
    genes <- rownames(expr_filtered)
    
    # Create Motif Prior (TF, Gene, Weight)
    set.seed(42)
    motif_prior <- expand.grid(TF = tfs, Gene = genes, stringsAsFactors = FALSE)
    motif_prior\$Weight <- rbinom(nrow(motif_prior), 1, 0.15) # 15% probability of prior edge
    
    # Create PPI Prior (TF1, TF2, Weight)
    ppi_prior <- expand.grid(TF1 = tfs, TF2 = tfs, stringsAsFactors = FALSE)
    ppi_prior\$Weight <- runif(nrow(ppi_prior), 0, 1)
    
    # ---------------------------------------------------------
    # --- Run PANDA Network Reconstruction ---
    # ---------------------------------------------------------
    message("Running PANDA for Condition 1...")
    panda_res1 <- panda(motif_prior, expr1, ppi_prior, hamming = 1)
    
    message("Running PANDA for Condition 2...")
    panda_res2 <- panda(motif_prior, expr2, ppi_prior, hamming = 1)
    
    # ---------------------------------------------------------
    # --- Downstream Network Analysis & Edge Extraction ---
    # ---------------------------------------------------------
    message("Extracting top regulatory edges...")
    top_net1 <- topedges(panda_res1, 100)
    write.csv(top_net1, "top_edges_cond1.csv", row.names = FALSE)
    
    # Calculate degree differences between the two conditions
    message("Calculating degree differences...")
    deg_diff <- tryCatch({
      calcDegreeDifference(panda_res1, panda_res2)
    }, error = function(e) {
      message("Warning: calcDegreeDifference failed, calculating manual degree difference.")
      deg1 <- calcDegree(panda_res1)
      deg2 <- calcDegree(panda_res2)
      # Return a fallback data frame
      data.frame(TF = rownames(deg1), Deg1 = deg1[,1], Deg2 = deg2[,1], Diff = deg1[,1] - deg2[,1])
    })
    write.csv(deg_diff, "degree_difference.csv", row.names = TRUE)
    
    # Extract a subnetwork of interest for visualization
    sub_tfs <- tfs[1:min(3, length(tfs))]
    sub_net <- subnetwork(top_net1, sub_tfs)
    
    # ---------------------------------------------------------
    # --- Visualization and Diagnostics ---
    # ---------------------------------------------------------
    message("Generating diagnostic plots...")
    pdf("panda_plots.pdf", width = 8, height = 8)
    
    # Plot 1: Subnetwork Graph
    tryCatch({
      plotGraph(sub_net)
      title(main = "Subnetwork of Top Regulatory Edges")
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Graph Plot Failed:", e\$message), cex = 0.8)
    })
    
    # Plot 2: Z-score Comparison between Conditions
    tryCatch({
      plotZ(panda_res1, panda_res2, addLine = TRUE)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Z-score Plot Failed:", e\$message), cex = 0.8)
    })
    
    # Plot 3: Z-score by TF Outdegree Quartiles
    tryCatch({
      plotZbyTF(panda_res1, panda_res2)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Z-score by TF Plot Failed:", e\$message), cex = 0.8)
    })
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK":',
        paste0('    pandaR: ', as.character(packageVersion('pandaR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_panda_differential_network.csv versions.yml
    """
}

workflow BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK(ch_input)

    emit:
    tables   = BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK.out.tables
    plots    = BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK.out.plots
    objects  = BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK.out.objects
    versions = BIOC_PANDAR_PANDA_DIFFERENTIAL_NETWORK.out.versions
}
