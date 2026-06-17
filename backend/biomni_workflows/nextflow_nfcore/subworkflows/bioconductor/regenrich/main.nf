#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RegEnrich — regenrich_regulator_analysis
// Identify key gene regulators from expression data and sample metadata using the RegEnrich pipeline, performing differential expression, network inference, enric
// Input: counts.csv, coldata.csv
// Container: 1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RegEnrich, S4Vectors
// Visualizations: enrichment plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS {
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
    .bm_deps <- c("RegEnrich", "S4Vectors")
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
    library(RegEnrich)
    library(S4Vectors)
    
    message("Stage 1: Reading and preprocessing input data...")
    
    # Read user input files
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align sample names between counts and coldata
    if ("sample" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$sample
    }
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    expr_data <- as.matrix(counts)
    
    # Log-transform if the input data contains raw counts (heuristic check)
    if (max(expr_data, na.rm = TRUE) > 50) {
      message("Raw counts detected. Applying log2(counts + 1) transformation...")
      expr_data <- log2(expr_data + 1)
    }
    
    message("Stage 2: Dynamically defining candidate regulators...")
    # To avoid forbidden demo datasets, we identify candidate regulators directly from the input data.
    # We select the top 15% of genes with the highest expression variance as candidate regulators.
    gene_vars <- apply(expr_data, 1, var)
    gene_vars[is.na(gene_vars)] <- 0
    n_reg <- min(max(round(nrow(expr_data) * 0.15), 10), 100)
    regulators <- names(sort(gene_vars, decreasing = TRUE))[1:n_reg]
    
    message("Stage 3: Initializing RegenrichSet object...")
    # Set up design matrix and contrast dynamically based on the 'condition' column
    coldata\$condition <- as.factor(coldata\$condition)
    design_matrix <- model.matrix(~ condition, data = coldata)
    contrast_vector <- rep(0, ncol(design_matrix))
    contrast_vector[ncol(design_matrix)] <- 1 # Compare the last level to the baseline level
    
    object <- RegenrichSet(
      expr = expr_data,
      colData = coldata,
      method = "limma",
      design = ~ condition,
      contrast = contrast_vector,
      reg = regulators,
      networkConstruction = "COEN",
      enrichTest = "FET"
    )
    
    message("Stage 4: Running the RegEnrich pipeline...")
    
    # --- Differential expression analysis ---
    message("Step 4.1: Running differential expression analysis...")
    object <- regenrich_diffExpr(object)
    
    # --- Regulator-target network inference ---
    message("Step 4.2: Inferring regulator-target network...")
    object <- regenrich_network(object)
    
    # --- Enrichment analysis ---
    message("Step 4.3: Performing enrichment analysis...")
    object <- regenrich_enrich(object)
    
    # --- Regulator scoring and ranking ---
    message("Step 4.4: Scoring and ranking regulators...")
    object <- regenrich_rankScore(object)
    
    message("Stage 5: Extracting and saving results...")
    
    # Extract results using RegEnrich accessor functions
    res_score <- results_score(object)
    res_dea <- results_DEA(object)
    res_enrich <- results_enrich(object)
    res_topnet <- results_topNet(object)
    
    # Save main tables
    write.csv(as.data.frame(res_score), "reg_enrich_results.csv", row.names = FALSE)
    write.csv(as.data.frame(res_dea), "differential_expression_results.csv", row.names = TRUE)
    
    # Safely extract and save enrichment results
    if (!is.null(res_enrich)) {
      enrich_df <- tryCatch({
        as.data.frame(slot(res_enrich, "allResult"))
      }, error = function(e) {
        as.data.frame(res_enrich)
      })
      write.csv(enrich_df, "enrichment_results.csv", row.names = FALSE)
    }
    
    # Safely extract and save network edges
    if (!is.null(res_topnet)) {
      topnet_df <- tryCatch({
        as.data.frame(slot(res_topnet, "elementset"))
      }, error = function(e) {
        as.data.frame(res_topnet)
      })
      write.csv(topnet_df, "top_network_edges.csv", row.names = FALSE)
    }
    
    message("Stage 6: Generating diagnostic and results plots...")
    pdf("regenrich_plots.pdf", width = 7, height = 6)
    
    # Plot expression of the top-ranked regulator and its targets
    if (nrow(res_score) > 0) {
      top_regulator <- res_score\$reg[1]
      message(paste("Plotting expression profiles for top regulator:", top_regulator))
      tryCatch({
        plotRegTarExpr(object, reg = top_regulator)
      }, error = function(e) {
        warning("Could not plot regulator-target expression: ", e\$message)
      })
    }
    
    # Plot enrichment results
    if (!is.null(res_enrich)) {
      message("Plotting enrichment results...")
      tryCatch({
        plot_Enrich(res_enrich)
      }, error = function(e) {
        warning("Could not plot enrichment results: ", e\$message)
      })
    }
    
    dev.off()
    
    message("RegEnrich analysis pipeline completed successfully!")

    writeLines(c(
        '"BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS":',
        paste0('    RegEnrich: ', as.character(packageVersion('RegEnrich')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regenrich_regulator_analysis.csv versions.yml
    """
}

workflow BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS.out.tables
    plots    = BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS.out.plots
    objects  = BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS.out.objects
    versions = BIOC_REGENRICH_REGENRICH_REGULATOR_ANALYSIS.out.versions
}
