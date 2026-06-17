#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regioneR — resampling_permutation_test
// Test the association of a subset of regions (e.g., special genes) against another genomic feature by resampling from a finite universe of valid regions (e.g., a
// Input: my.special.genes.txt, all.genes.txt, my.altered.regions.txt
// Container: quay.io/biocontainers/bioconductor-regioner:1.42.0--r45hdfd78af_0
// R packages: regioneR
// Bioconductor: 3.20 | R: 4.4
// Requires: regioneR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load region sets using toGRanges
//  * 2. [Core Analysis] Run the permutation test using permTest with resampleRegions as the randomization function
//  * 3. [Visualization & Output] Summarize and plot the results using summary and plot

nextflow.enable.dsl = 2

process BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("regioneR")
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
        library(regioneR)
        
        # Define input file paths
        special_file <- "my.special.genes.txt"
        all_genes_file <- "all.genes.txt"
        altered_file <- "my.altered.regions.txt"
        
        # Verify that all required input files exist in the working directory
        if (!file.exists(special_file)) {
          stop(paste("Error: Required input file missing:", special_file))
        }
        if (!file.exists(all_genes_file)) {
          stop(paste("Error: Required input file missing:", all_genes_file))
        }
        if (!file.exists(altered_file)) {
          stop(paste("Error: Required input file missing:", altered_file))
        }
        
        # Set seed for reproducibility
        set.seed(12345)
        
        # 1. Load region sets using toGRanges
        special <- toGRanges(special_file)
        all.genes <- toGRanges(all_genes_file)
        altered <- toGRanges(altered_file)
        
        # 2. Run the permutation test using permTest with resampleRegions as the randomization function
        pt <- permTest(A=special, ntimes=50, randomize.function=resampleRegions, universe=all.genes, evaluate.function=numOverlaps, B=altered, verbose=FALSE)
        
        # 3. Summarize and plot the results
        # Print to console
        pt
        summary(pt)
        
        # Save the permutation test object as an RDS file
        saveRDS(pt, "permutation_test_results.rds")
        
        # Save the text summary to a file
        sink("permutation_test_summary.txt")
        cat("=== PERMUTATION TEST RESULTS ===\n")
        print(pt)
        cat("\n=== SUMMARY ===\n")
        print(summary(pt))
        sink()
        
        # Extract results to a CSV table
        results_df <- data.frame(
          test = names(pt),
          p_value = sapply(pt, function(x) x\$pval),
          zscore = sapply(pt, function(x) x\$zscore),
          observed = sapply(pt, function(x) x\$observed),
          mean_permuted = sapply(pt, function(x) mean(x\$permuted)),
          alternative = sapply(pt, function(x) x\$alternative),
          stringsAsFactors = FALSE
        )
        write.csv(results_df, "permutation_test_results.csv", row.names = FALSE)
        
        # Save the plot as a PDF file
        pdf("permutation_test_plot.pdf", width = 8, height = 6)
        plot(pt)
        dev.off()

    writeLines(c(
        '"BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST":',
        paste0('    regioneR: ', as.character(packageVersion('regioneR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_resampling_permutation_test.csv versions.yml
    """
}

workflow BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my.special.genes.txt, all.genes.txt, my.altered.regions.txt ] ]

    main:
    BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST(ch_input)

    emit:
    tables   = BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST.out.tables
    plots    = BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST.out.plots
    objects  = BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST.out.objects
    versions = BIOC_REGIONER_RESAMPLING_PERMUTATION_TEST.out.versions
}
