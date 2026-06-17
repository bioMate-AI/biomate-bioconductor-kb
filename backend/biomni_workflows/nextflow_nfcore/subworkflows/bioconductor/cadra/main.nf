#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CaDrA — candidate_driver_analysis
// Identify a subset of binary genomic features (meta-features) maximally associated with a continuous functional score, visualize the top candidates, and evaluate
// Input: binary_features.csv, functional_scores.csv
// Container: quay.io/biocontainers/bioconductor-cadra:1.8.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CaDrA, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read in binary features
//  * 2. [Visualization & Output] Read in input score

nextflow.enable.dsl = 2

process BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS {
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
    .bm_deps <- c("CaDrA", "SummarizedExperiment")
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
    
    # Load R packages
    library(SummarizedExperiment)
    library(CaDrA)
    
    # --- Read in binary features ---
    if (!file.exists("binary_features.csv")) {
      stop("Error: binary_features.csv not found in the working directory.")
    }
    bin_feat_df <- read.csv("binary_features.csv", row.names = 1, header = TRUE, check.names = FALSE)
    FS_mat <- as.matrix(bin_feat_df)
    eset_mut_scna <- SummarizedExperiment::SummarizedExperiment(assays = list(FS_mat))
    
    # --- Read in input score ---
    if (!file.exists("functional_scores.csv")) {
      stop("Error: functional_scores.csv not found in the working directory.")
    }
    scores_df <- read.csv("functional_scores.csv", header = TRUE, stringsAsFactors = FALSE)
    if (ncol(scores_df) == 1) {
      scores_df <- read.csv("functional_scores.csv", row.names = 1, header = TRUE, check.names = FALSE)
      input_score <- as.numeric(scores_df[[1]])
      names(input_score) <- rownames(scores_df)
    } else {
      input_score <- as.numeric(scores_df[, 2])
      names(input_score) <- as.character(scores_df[, 1])
    }
    
    # Samples to keep based on the overlap between the two inputs
    overlap <- base::intersect(base::names(input_score), base::colnames(eset_mut_scna))
    if (length(overlap) == 0) {
      stop("Error: No overlapping samples found between binary_features.csv and functional_scores.csv")
    }
    eset_mut_scna <- eset_mut_scna[, overlap]
    input_score <- input_score[overlap]
    
    # Binarize FS to only have 0's and 1's
    SummarizedExperiment::assay(eset_mut_scna)[SummarizedExperiment::assay(eset_mut_scna) > 1] <- 1.0
    
    # Pre-filter FS based on occurrence frequency
    eset_mut_scna_flt <- CaDrA::prefilter_data(
      FS = eset_mut_scna,
      max_cutoff = 0.6, # max event frequency (60%)
      min_cutoff = 0.03 # min event frequency (3%)
    )
    
    # Determine safe top_N and max_size based on filtered features
    num_features <- nrow(eset_mut_scna_flt)
    if (num_features == 0) {
      stop("Error: No features left after pre-filtering. Adjust max_cutoff/min_cutoff or check input data.")
    }
    top_N_val <- min(7, num_features)
    max_size_val <- min(7, num_features)
    max_size_perm <- min(10, num_features)
    
    # Run candidate search
    topn_res <- CaDrA::candidate_search(
      FS = eset_mut_scna_flt,
      input_score = input_score,
      method = "ks_pval", # Use Kolmogorow-Smirnow scoring function
      method_alternative = "less", # Use one-sided hypothesis testing
      weights = NULL, # If weights is provided, perform a weighted-KS test
      search_method = "both", # Apply both forward and backward search
      top_N = top_N_val, # Evaluate top N starting points for each search
      max_size = max_size_val, # Maximum size a meta-feature matrix can extend to
      do_plot = FALSE, # Plot after finding the best features
      best_score_only = FALSE # Return all results from the search
    )
    
    # Fetch the meta-feature set corresponding to its best scores over top N features searches
    topn_best_meta <- CaDrA::topn_best(topn_res)
    
    # Save RDS of search results and best meta-features
    saveRDS(topn_res, "candidate_search_results.rds")
    saveRDS(topn_best_meta, "topn_best_meta.rds")
    
    # Visualize the best results with the meta-feature plot
    pdf("meta_plot.pdf", width = 10, height = 8)
    CaDrA::meta_plot(topn_best_list = topn_best_meta, input_score_label = "YAP/TAZ Activity")
    dev.off()
    
    # Evaluate results across top N features you started from
    pdf("topn_plot.pdf", width = 8, height = 6)
    CaDrA::topn_plot(topn_res)
    dev.off()
    
    # Set seed for permutation-based testing
    set.seed(123)
    
    perm_res <- CaDrA::CaDrA(
      FS = eset_mut_scna_flt, 
      input_score = input_score, 
      method = "ks_pval",             # Use Kolmogorow-Smirnow scoring function 
      method_alternative = "less",    # Use one-sided hypothesis testing
      weights = NULL,                 # If weights is provided, perform a weighted-KS test
      search_method = "both",         # Apply both forward and backward search
      top_N = top_N_val,              # Repeat the search with the top N features
      max_size = max_size_perm,       # Allow at most 10 features in the meta-feature matrix
      n_perm = 100,                   # Number of permutations to perform
      perm_alternative = "one.sided", # One-sided permutation-based p-value alternative type
      plot = FALSE,                   # We will plot later
      ncores = 1                      # Number of cores to perform parallelization (set to 1 for safety)
    )
    
    # Save RDS of permutation results
    saveRDS(perm_res, "permutation_results.rds")
    
    # Visualize permutation results
    pdf("permutation_plot.pdf", width = 8, height = 6)
    CaDrA::permutation_plot(perm_res = perm_res)
    dev.off()
    
    # Write out a summary of the best meta-features to a text file
    sink("best_meta_features_summary.txt")
    cat("Best Meta-Features Summary:\n")
    print(topn_best_meta)
    sink()

    writeLines(c(
        '"BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS":',
        paste0('    CaDrA: ', as.character(packageVersion('CaDrA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_candidate_driver_analysis.csv versions.yml
    """
}

workflow BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ binary_features.csv, functional_scores.csv ] ]

    main:
    BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS.out.tables
    plots    = BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS.out.plots
    objects  = BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS.out.objects
    versions = BIOC_CADRA_CANDIDATE_DRIVER_ANALYSIS.out.versions
}
