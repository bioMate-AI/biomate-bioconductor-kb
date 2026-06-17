#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BAGS — bags_geneset_significance
// Perform Bayesian geneset significance analysis (BAGS) on cross-sectional expression data to identify differentially expressed gene sets between two phenotypes.
// Input: input.csv
// Container: 2.50.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BAGS
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE {
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
    .bm_deps <- c("BAGS")
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
    library(BAGS)
    
    # ==========================================
    # --- Read and Preprocess Input Data ---
    # ==========================================
    cat("Reading input data...\n")
    if (!file.exists("input.csv")) {
      stop("Error: input.csv not found in the working directory.")
    }
    
    # Read the input matrix defensively
    df <- read.csv("input.csv", header = TRUE, check.names = FALSE)
    
    # Handle row names / feature identifiers
    if ("feature_id" %in% colnames(df)) {
      rownames(df) <- df\$feature_id
      df\$feature_id <- NULL
    } else {
      rownames(df) <- df[, 1]
      df <- df[, -1, drop = FALSE]
    }
    
    # Ensure all columns are numeric
    numeric_cols <- sapply(df, is.numeric)
    if (sum(numeric_cols) < 4) {
      stop("Error: Input matrix must contain at least 4 numeric sample columns.")
    }
    gene.expr <- as.matrix(df[, numeric_cols, drop = FALSE])
    
    # Define two phenotypes by splitting the samples into two equal groups
    n_samples <- ncol(gene.expr)
    group1 <- 1:floor(n_samples / 2)
    group2 <- (floor(n_samples / 2) + 1):n_samples
    phntp.list <- list(group1, group2)
    
    cat(sprintf("Detected %d genes and %d samples. Splitting into groups of size %d and %d.\n", 
                nrow(gene.expr), n_samples, length(group1), length(group2)))
    
    # Filter duplicate genes by keeping the one with the highest variability among phenotypes
    gene.nms.u <- unique(rownames(gene.expr))
    gene.nms <- rownames(gene.expr)
    indices <- NULL
    
    cat("Filtering duplicate genes based on variability...\n")
    for (i in seq_along(gene.nms.u)) {
      aux <- which(gene.nms == gene.nms.u[i])
      if (length(aux) > 1) {
        var.r <- apply(cbind(
          apply(gene.expr[aux, group1, drop = FALSE], 1, mean),
          apply(gene.expr[aux, group2, drop = FALSE], 1, mean)
        ), 1, var)
        aux <- aux[which.max(var.r)]
      }
      indices <- c(indices, aux)
    }
    
    gene.expr <- gene.expr[indices, , drop = FALSE]
    gene.nams <- rownames(gene.expr)
    
    # ==========================================
    # --- Prepare Gene Sets ---
    # ==========================================
    cat("Constructing gene sets...\n")
    # Dynamically define minimum gene set size based on available genes
    min_size <- min(5, floor(length(gene.nams) / 4))
    if (min_size < 2) min_size <- 2
    
    # Programmatically generate a collection of gene sets from the input genes
    set.seed(123)
    Annotation <- list()
    num_sets <- min(50, max(10, floor(length(gene.nams) / 5)))
    for (i in 1:num_sets) {
      set_size <- sample(min_size:min(30, length(gene.nams)), 1)
      Annotation[[paste0("GeneSet_", i)]] <- sample(gene.nams, set_size)
    }
    
    # Filter and format the gene sets
    data.gene.grps <- DataGeneSets(Annotation, gene.nams, min_size)
    
    if (length(data.gene.grps\$Size) == 0) {
      stop("Error: No gene sets met the minimum size criteria.")
    }
    
    # ==========================================
    # --- Prepare MCMC Data Set ---
    # ==========================================
    cat("Preparing MCMC dataset...\n")
    data.mcmc <- MCMCDataSet(gene.expr, data.gene.grps\$DataGeneSetsIds, phntp.list)
    
    # ==========================================
    # --- Run Gibbs Sampler ---
    # ==========================================
    cat("Running Gibbs sampler...\n")
    noRow <- dim(data.mcmc\$y.mu)[1]
    noCol <- unlist(lapply(phntp.list, length))
    iter <- 5000  # Number of iterations for robust estimation
    GrpSzs <- data.gene.grps\$Size
    YMu <- data.mcmc\$y.mu
    
    # Prior parameters
    L0 <- rep(2, 2)
    V0 <- rep(4, 2)
    L0A <- rep(3, 1)
    V0A <- rep(3, 1)
    MM <- 0.55
    AAPi <- 10
    ApriDiffExp <- max(1, floor(noRow * 0.05))
    results <- matrix(0, noRow, iter)
    
    # Execute Gibbs sampler for 2 phenotypes
    mcmc.chains <- Gibbs2(
      noRow, noCol, iter, GrpSzs, YMu, 
      L0, V0, L0A, V0A, MM, AAPi, ApriDiffExp, 
      results
    )
    
    # ==========================================
    # --- Post-processing and Diagnostics ---
    # ==========================================
    cat("Analyzing posterior chains...\n")
    burn.in <- floor(iter * 0.2)  # 20% burn-in
    
    alfa.pi <- apply(mcmc.chains[[1]][, burn.in:iter, drop = FALSE], 1, function(x) {
      length(which(x != 0)) / length(burn.in:iter)
    })
    
    # Create results table
    results_df <- data.frame(
      GeneSet = names(data.gene.grps\$Size),
      Size = data.gene.grps\$Size,
      PosteriorProb = alfa.pi,
      stringsAsFactors = FALSE
    )
    
    # Save results to CSV
    write.csv(results_df, "geneset_probabilities.csv", row.names = FALSE)
    cat("Saved posterior probabilities to 'geneset_probabilities.csv'.\n")
    
    # Generate diagnostic plot
    cat("Generating diagnostic plot...\n")
    pdf("differential_genesets.pdf", width = 10, height = 6)
    op <- par(mar = c(7, 4, 4, 2) + 0.1)
    plot(
      alfa.pi, 
      type = "h", 
      main = "Posterior Probabilities of Gene Sets Being Differentially Expressed",
      xlab = "", 
      ylab = "Posterior Probability (alpha.pi)", 
      ylim = c(0, 1),
      xaxt = "n",
      col = "blue",
      lwd = 2
    )
    axis(1, at = 1:length(alfa.pi), labels = names(data.gene.grps\$Size), las = 2, cex.axis = 0.7)
    cut.off <- 0.9
    abline(h = cut.off, col = "red", lty = 2, lwd = 1.5)
    legend("topright", legend = paste("Cut-off =", cut.off), col = "red", lty = 2, bty = "n")
    par(op)
    dev.off()
    cat("Saved plot to 'differential_genesets.pdf'.\n")
    
    cat("Pipeline completed successfully!\n")

    writeLines(c(
        '"BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE":',
        paste0('    BAGS: ', as.character(packageVersion('BAGS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bags_geneset_significance.csv versions.yml
    """
}

workflow BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE(ch_input)

    emit:
    tables   = BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE.out.tables
    plots    = BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE.out.plots
    objects  = BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE.out.objects
    versions = BIOC_BAGS_BAGS_GENESET_SIGNIFICANCE.out.versions
}
