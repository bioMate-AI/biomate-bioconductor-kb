#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mina — statistical_network_comparison
// Compare ecological networks across different sample groups and statistically assess their dissimilarity using bootstrap-permutation.
// Input: maize
// Container: quay.io/biocontainers/bioconductor-mina:1.18.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mina
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Align tables
//  * 2. [Input & Preparation] Run bootstrap-permutation to construct true and pseudo networks
//  * 3. [Core Analysis] Calculate network distances (Spectral or Jaccard)
//  * 4. [Core Analysis] Assess significance and extract distance statistics

nextflow.enable.dsl = 2

process BIOC_MINA_STATISTICAL_NETWORK_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20"

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
    .bm_deps <- c("mina")
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
            
            # Load the required library
            library(mina)
            
            # Read the input maize object from the working directory
            maize <- readRDS("maize")
            
            # Define and create the output directory for individual comparison results
            out_dir <- "out_dir"
            if (!dir.exists(out_dir)) {
              dir.create(out_dir, recursive = TRUE)
            }
            
            # 1. Align tables
            maize <- fit_tabs(maize)
            
            # 2. Run bootstrap-permutation to construct true and pseudo networks
            # Identify a grouping column from the descriptive table (excluding Sample_ID)
            group_col <- setdiff(colnames(maize@des), "Sample_ID")[1]
            
            # Determine safe g_size and s_size based on the data to avoid filtering out valid groups
            group_counts <- sort(table(maize@des[[group_col]]), decreasing = TRUE)
            g_size_val <- as.numeric(group_counts[min(2, length(group_counts))])
            s_size_val <- max(2, floor(g_size_val / 2))
            
            # Compare the networks from different groups, setting parameters to filter and bootstrap
            maize <- bs_pm(maize, group = group_col, g_size = g_size_val, s_size = s_size_val, per = 0.2, bs = 11, pm = 11)
            
            # Output the comparison separately to the defined directory
            bs_pm(maize, group = group_col, g_size = g_size_val, s_size = s_size_val, bs = 6, pm = 6,
                  individual = TRUE, out_dir = out_dir)
            
            # 3. Calculate network distances (Spectral and Jaccard)
            maize <- net_dis(maize, method = "spectra")
            maize <- net_dis(maize, method = "Jaccard")
            
            # 4. Assess significance and extract distance statistics
            # Check the distance results and significance for the combined object
            maize_stats <- dis_stat(maize)
            if (!is.null(maize_stats)) {
              write.csv(maize_stats, "maize_distance_stats.csv", row.names = FALSE)
            }
            
            # Calculate and extract distance statistics for individual comparisons stored separately
            ja <- net_dis_indi(out_dir, method = "Jaccard")
            ja_stats <- dis_stat(ja)
            if (!is.null(ja_stats)) {
              write.csv(ja_stats, "jaccard_individual_distance_stats.csv", row.names = FALSE)
            }
            
            spectra <- net_dis_indi(out_dir, method = "spectra")
            spectra_stats <- dis_stat(spectra)
            if (!is.null(spectra_stats)) {
              write.csv(spectra_stats, "spectra_individual_distance_stats.csv", row.names = FALSE)
            }
            
            # Save the final modified maize object
            saveRDS(maize, "maize_output.rds")

    writeLines(c(
        '"BIOC_MINA_STATISTICAL_NETWORK_COMPARISON":',
        paste0('    mina: ', as.character(packageVersion('mina')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_statistical_network_comparison.csv versions.yml
    """
}

workflow BIOC_MINA_STATISTICAL_NETWORK_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ maize ] ]

    main:
    BIOC_MINA_STATISTICAL_NETWORK_COMPARISON(ch_input)

    emit:
    tables   = BIOC_MINA_STATISTICAL_NETWORK_COMPARISON.out.tables
    plots    = BIOC_MINA_STATISTICAL_NETWORK_COMPARISON.out.plots
    objects  = BIOC_MINA_STATISTICAL_NETWORK_COMPARISON.out.objects
    versions = BIOC_MINA_STATISTICAL_NETWORK_COMPARISON.out.versions
}
