#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: roar — standard_apa_analysis
// Identify differential alternative polyadenylation (APA) usage between two biological conditions using RNA-seq BAM files and a PRE/POST annotated GTF file.
// Input: bamTreatment, bamControl, gtf
// Container: quay.io/biocontainers/bioconductor-roar:1.46.0--r45hdfd78af_0
// R packages: roar, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ROAR_STANDARD_APA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-roar:1.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("roar", "rtracklayer")
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
    
    # ==============================================================================
    # Pipeline: standard_apa_analysis using the 'roar' package
    # Intent: Identify differential alternative polyadenylation (APA) usage 
    #         between two biological conditions using RNA-seq BAM files and 
    #         a PRE/POST annotated GTF file.
    # ==============================================================================
    
    library(roar)
    library(rtracklayer)
    
    # ------------------------------------------------------------------------------
    # 1. Locate and Validate User Input Files
    # ------------------------------------------------------------------------------
    cat("Scanning working directory for input files...\n")
    
    # Locate GTF file
    gtf_files <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)
    if (length(gtf_files) == 0) {
      stop("Error: No GTF file found in the working directory. Please provide a PRE/POST annotated GTF file.")
    }
    gtf <- gtf_files[1]
    cat("Using GTF file:", gtf, "\n")
    
    # Locate Treatment BAM files
    bamTreatment <- list.files(pattern = "treatment.*\\\\.bam\$", full.names = TRUE)
    if (length(bamTreatment) == 0) {
      stop("Error: No treatment BAM files found. Please ensure files match the pattern 'treatment*.bam'.")
    }
    cat("Found", length(bamTreatment), "treatment BAM file(s):\n")
    print(bamTreatment)
    
    # Locate Control BAM files
    bamControl <- list.files(pattern = "control.*\\\\.bam\$", full.names = TRUE)
    if (length(bamControl) == 0) {
      stop("Error: No control BAM files found. Please ensure files match the pattern 'control*.bam'.")
    }
    cat("Found", length(bamControl), "control BAM file(s):\n")
    print(bamControl)
    
    # ------------------------------------------------------------------------------
    # 2. Initialize the RoarDataset Object
    # ------------------------------------------------------------------------------
    cat("\nInitializing RoarDataset object...\n")
    rds <- RoarDatasetFromFiles(bamTreatment, bamControl, gtf)
    
    # ------------------------------------------------------------------------------
    # 3. Count Reads Overlapping PRE and POST Portions
    # ------------------------------------------------------------------------------
    cat("Counting reads overlapping PRE and POST portions (stranded = FALSE)...\n")
    rds <- countPrePost(rds, FALSE)
    
    # ------------------------------------------------------------------------------
    # 4. Compute the Ratio of Prevalence (m/M) and Roar Values
    # ------------------------------------------------------------------------------
    cat("Computing m/M ratios and roar values...\n")
    rds <- computeRoars(rds)
    
    # ------------------------------------------------------------------------------
    # 5. Compute P-values Using Fisher's Exact Test
    # ------------------------------------------------------------------------------
    cat("Computing p-values...\n")
    rds <- computePvals(rds)
    
    # ------------------------------------------------------------------------------
    # 6. Extract and Filter Results
    # ------------------------------------------------------------------------------
    cat("Extracting total results...\n")
    results <- totalResults(rds)
    
    cat("Filtering results (fpkmCutoff = -Inf, pvalCutoff = 0.05)...\n")
    results_filtered <- pvalueFilter(rds, fpkmCutoff=-Inf, pvalCutoff=0.05)
    
    # Report summary statistics
    if ("nUnderCutoff" %in% colnames(results_filtered)) {
      n_comparisons <- length(bamTreatment) * length(bamControl)
      matching_rows <- nrow(results_filtered[results_filtered\$nUnderCutoff == n_comparisons, , drop=FALSE])
      cat(sprintf("\nNumber of genes with p-value < 0.05 across all %d comparisons: %d\n", 
                  n_comparisons, matching_rows))
    } else {
      cat("\nNumber of genes with p-value < 0.05:", nrow(results_filtered), "\n")
    }
    
    # ------------------------------------------------------------------------------
    # 7. Export Outputs
    # ------------------------------------------------------------------------------
    cat("\nExporting results to output files...\n")
    
    # Save tables
    write.csv(results, file = "roar_results_all.csv", row.names = TRUE)
    write.csv(results_filtered, file = "roar_results_filtered.csv", row.names = TRUE)
    cat("Saved results tables: 'roar_results_all.csv' and 'roar_results_filtered.csv'\n")
    
    # Save RDS object for downstream analysis
    saveRDS(rds, file = "roar_dataset.rds")
    cat("Saved RoarDataset object: 'roar_dataset.rds'\n")
    
    # Generate diagnostic plots
    pdf("roar_diagnostic_plots.pdf", width = 8, height = 6)
    par(mfrow = c(1, 2))
    
    # Plot 1: Distribution of Roar values (log2 scale for visualization)
    valid_roars <- results\$roar[!is.na(results\$roar) & is.finite(results\$roar) & results\$roar > 0]
    if (length(valid_roars) > 0) {
      hist(log2(valid_roars), 
           main = "Distribution of Roar Values", 
           xlab = "log2(Roar)", 
           col = "skyblue", 
           breaks = 20)
    } else {
      plot(1, type="n", axes=FALSE, xlab="", ylab="", main="No valid Roar values to plot")
    }
    
    # Plot 2: Distribution of P-values
    valid_pvals <- results\$pval[!is.na(results\$pval)]
    if (length(valid_pvals) > 0) {
      hist(valid_pvals, 
           main = "Distribution of P-values", 
           xlab = "P-value", 
           col = "salmon", 
           breaks = 20)
    } else {
      plot(1, type="n", axes=FALSE, xlab="", ylab="", main="No valid P-values to plot")
    }
    
    dev.off()
    cat("Saved diagnostic plots: 'roar_diagnostic_plots.pdf'\n")
    
    cat("\nPipeline completed successfully!\n")

    writeLines(c(
        '"BIOC_ROAR_STANDARD_APA_ANALYSIS":',
        paste0('        roar: ', as.character(packageVersion("roar")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_apa_analysis.csv versions.yml
    """
}

workflow BIOC_ROAR_STANDARD_APA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamTreatment, bamControl, gtf ] ]

    main:
    BIOC_ROAR_STANDARD_APA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ROAR_STANDARD_APA_ANALYSIS.out.tables
    plots    = BIOC_ROAR_STANDARD_APA_ANALYSIS.out.plots
    objects  = BIOC_ROAR_STANDARD_APA_ANALYSIS.out.objects
    versions = BIOC_ROAR_STANDARD_APA_ANALYSIS.out.versions
}
