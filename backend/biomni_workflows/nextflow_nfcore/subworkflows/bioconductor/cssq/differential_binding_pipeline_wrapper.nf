#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CSSQ — differential_binding_pipeline_wrapper
// Run the complete preprocessing (counting/loading, transformation, and normalization) and differential binding analysis using the all-in-one wrapper function.
// Input: chr19_regions.bed, sample_info.txt, BAM files
// Container: quay.io/biocontainers/bioconductor-cssq:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CSSQ, GenomicRanges
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess data in a single step using preprocessData
//  * 2. [Core Analysis] Perform non-parametric statistical testing for differential binding using DBAnalyze

nextflow.enable.dsl = 2

process BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("CSSQ", "GenomicRanges")
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
    library(CSSQ)
    library(GenomicRanges)
    
    # Define input file paths
    bed_file <- "chr19_regions.bed"
    sample_info_file <- "sample_info.txt"
    count_file <- "sample_count_data.txt"
    
    # Verify that essential input files exist
    if (!file.exists(bed_file)) {
      stop(paste("Error: Required BED file missing:", bed_file))
    }
    if (!file.exists(sample_info_file)) {
      stop(paste("Error: Required sample info file missing:", sample_info_file))
    }
    
    # Read sample info to inspect groups
    sample_info <- read.table(sample_info_file, sep = "\t", header = TRUE, stringsAsFactors = FALSE)
    message("Sample info loaded successfully. Groups present: ", paste(unique(sample_info\$Group), collapse = ", "))
    
    # Determine which preprocessing path to take based on input file availability
    if (file.exists(count_file)) {
      message("Found pre-calculated count data. Running preprocessData with inputCountData...")
      processedData <- preprocessData(
        bed_file,
        sample_info_file,
        inputCountData = count_file,
        numClusters = 4,
        noNeg = TRUE,
        plotData = FALSE
      )
    } else {
      message("Pre-calculated count data not found. Running preprocessData with BAM files in current directory...")
      processedData <- preprocessData(
        bed_file,
        sample_info_file,
        sampleDir = ".",
        numClusters = 4,
        noNeg = TRUE,
        plotData = FALSE
      )
    }
    
    # Determine comparison groups (defaulting to "HSMM" and "HESC" as documented, with fallback)
    comparison_groups <- c("HSMM", "HESC")
    if (!all(comparison_groups %in% sample_info\$Group)) {
      warning("Documented comparison groups 'HSMM' and 'HESC' not found in sample_info.txt.")
      comparison_groups <- unique(sample_info\$Group)[1:2]
      message("Using alternative comparison groups found in metadata: ", paste(comparison_groups, collapse = " vs "))
    }
    
    # Perform differential binding analysis
    message("Running DBAnalyze...")
    result <- DBAnalyze(processedData, comparison = comparison_groups)
    
    # Save outputs
    message("Saving results...")
    
    # 1. Save RDS objects for downstream R analysis
    saveRDS(processedData, "processed_data.rds")
    saveRDS(result, "db_results.rds")
    
    # 2. Save results table as CSV
    result_df <- as.data.frame(result)
    write.csv(result_df, "differential_binding_results.csv", row.names = FALSE)
    
    # 3. Generate and save diagnostic volcano plot
    pdf("differential_binding_volcano_plot.pdf", width = 7, height = 7)
    if ("FC" %in% colnames(result_df) && "adj.pval" %in% colnames(result_df)) {
      plot(
        result_df\$FC, 
        -log10(result_df\$adj.pval), 
        xlab = "Fold Change (FC)", 
        ylab = "-log10(Adjusted P-value)", 
        main = paste("Differential Binding:", comparison_groups[1], "vs", comparison_groups[2]),
        pch = 20, 
        col = ifelse(result_df\$adj.pval < 0.05, "red", "black")
      )
      abline(h = -log10(0.05), col = "blue", lty = 2)
      legend("topright", legend = c("Significant (FDR < 0.05)", "Not Significant"), col = c("red", "black"), pch = 20)
    } else {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "Could not generate volcano plot: missing FC or adj.pval columns.")
    }
    dev.off()
    
    message("Pipeline completed successfully.")
    message("Outputs written to:")
    message("- 'processed_data.rds'")
    message("- 'db_results.rds'")
    message("- 'differential_binding_results.csv'")
    message("- 'differential_binding_volcano_plot.pdf'")

    writeLines(c(
        '"BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER":',
        paste0('    CSSQ: ', as.character(packageVersion('CSSQ')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_binding_pipeline_wrapper.csv versions.yml
    """
}

workflow BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr19_regions.bed, sample_info.txt, BAM files ] ]

    main:
    BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER(ch_input)

    emit:
    tables   = BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER.out.tables
    plots    = BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER.out.plots
    objects  = BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER.out.objects
    versions = BIOC_CSSQ_DIFFERENTIAL_BINDING_PIPELINE_WRAPPER.out.versions
}
