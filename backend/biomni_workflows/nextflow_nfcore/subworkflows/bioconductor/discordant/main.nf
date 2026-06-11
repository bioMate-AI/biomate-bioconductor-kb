#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: discordant — within_omics_discordant
// Identify pairs of genes that are differentially correlated between two phenotypic groups using a mixture model.
// Input: counts.csv, coldata.csv
// Container: 1.34.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: discordant
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT {
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
    .bm_deps <- c("discordant")
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
    library(discordant)
    
    # --- Read input files ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # --- Align samples between expression matrix and metadata ---
    common_samples <- intersect(colnames(counts_df), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv.")
    }
    
    counts_matrix <- as.matrix(counts_df[, common_samples])
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # --- Prepare group vector (must contain 1s and 2s for the two ---
    cond_factor <- as.factor(coldata\$condition)
    if (length(levels(cond_factor)) != 2) {
      stop("Discordant analysis requires exactly two phenotypic groups in the 'condition' column.")
    }
    groups <- as.numeric(cond_factor)
    
    # --- Filter outliers using the split MAD approach ---
    message("Filtering outliers using split MAD...")
    filtered_res <- splitMADOutlier(counts_matrix, filter0 = TRUE, threshold = 4)
    counts_filtered <- filtered_res\$mat.filtered
    
    # Fallback if filtering is too stringent
    if (nrow(counts_filtered) < 5) {
      message("Warning: Too few features remained after MAD filtering. Proceeding with unfiltered matrix.")
      counts_filtered <- counts_matrix
    }
    
    # --- Create correlation vectors for both groups ---
    message("Generating correlation vectors...")
    vectors <- createVectors(x = counts_filtered, groups = groups, cor.method = "spearman")
    
    # --- Run the Discordant mixture model algorithm ---
    message("Running Discordant algorithm...")
    result <- tryCatch({
      discordantRun(v1 = vectors\$v1, v2 = vectors\$v2, x = counts_filtered, components = 3)
    }, error = function(e) {
      message("Error during discordantRun: ", e\$message)
      return(NULL)
    })
    
    # --- Process and save outputs ---
    if (!is.null(result)) {
      # Create a tidy table of gene pairs and their posterior probabilities
      pp_vector <- result\$discordPPVector
      class_vector <- result\$classVector
      
      results_df <- data.frame(
        Feature_Pair = names(pp_vector),
        Posterior_Probability = pp_vector,
        Assigned_Class = class_vector,
        stringsAsFactors = FALSE
      )
      
      # Sort by posterior probability of differential correlation (descending)
      results_df <- results_df[order(results_df\$Posterior_Probability, decreasing = TRUE), ]
      
      # Write outputs
      write.csv(results_df, "differential_correlation_pairs.csv", row.names = FALSE)
      write.csv(as.data.frame(result\$discordPPMatrix), "discord_pp_matrix.csv", row.names = TRUE)
      message("Analysis completed successfully. Outputs written.")
    } else {
      # Write empty/informative fallback files if the algorithm failed
      fail_df <- data.frame(Error = "Discordant run failed. Check if feature size or sample size is sufficient.")
      write.csv(fail_df, "differential_correlation_pairs.csv", row.names = FALSE)
      write.csv(fail_df, "discord_pp_matrix.csv", row.names = FALSE)
      message("Analysis failed. Fallback files written.")
    }

    writeLines(c(
        '"BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT":',
        paste0('    discordant: ', as.character(packageVersion('discordant')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_within_omics_discordant.csv versions.yml
    """
}

workflow BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT(ch_input)

    emit:
    tables   = BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT.out.tables
    plots    = BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT.out.plots
    objects  = BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT.out.objects
    versions = BIOC_DISCORDANT_WITHIN_OMICS_DISCORDANT.out.versions
}
