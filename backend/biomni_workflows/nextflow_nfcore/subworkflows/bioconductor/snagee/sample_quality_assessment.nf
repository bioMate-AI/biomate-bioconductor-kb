#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SNAGEE — sample_quality_assessment
// Determine the relative signal-to-noise ratios (SNRs) of individual samples within a study to flag potentially problematic samples.
// Input: ALL
// Container: quay.io/biocontainers/bioconductor-snagee:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, SNAGEE
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Save the quality scores to a CSV table
//  * 2. [Input & Preparation] Save only the flagged samples to a separate CSV table
//  * 3. [Input & Preparation] Save the raw quality scores as an RDS object
//  * 4. [Input & Preparation] Generate a PDF plot of the quality scores

nextflow.enable.dsl = 2

process BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load the SNAGEE package
    library(SNAGEE)
    
    # Read the user input file 'ALL' from the working directory
    # We support RDS (for ExpressionSet or matrix) and CSV/TSV (for matrix)
    if (file.exists("ALL.rds")) {
      ALL <- readRDS("ALL.rds")
    } else if (file.exists("ALL.csv")) {
      ALL <- as.matrix(read.csv("ALL.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("ALL.tsv")) {
      ALL <- as.matrix(read.delim("ALL.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Input file 'ALL' (as ALL.rds, ALL.csv, or ALL.tsv) not found in the working directory.")
    }
    
    # Ensure no missing values (as required by qualSample)
    if (inherits(ALL, "ExpressionSet")) {
      has_na <- any(is.na(Biobase::exprs(ALL)))
    } else {
      has_na <- any(is.na(ALL))
    }
    
    if (has_na) {
      stop("Error: Input data contains missing values (NAs). SNAGEE::qualSample requires data with no missing values.")
    }
    
    # Calculate individual sample quality scores using qualSample
    qs = qualSample(ALL, multicore=FALSE)
    
    # Identify samples with quality scores below the threshold of -5
    flagged_count = sum(qs < -5)
    
    # Write named output files for the meaningful results
    # --- Save the quality scores to a CSV table ---
    qs_df <- data.frame(
      Sample = names(qs),
      QualityScore = qs,
      Flagged = qs < -5,
      stringsAsFactors = FALSE
    )
    write.csv(qs_df, "sample_quality_scores.csv", row.names = FALSE)
    
    # --- Save only the flagged samples to a separate CSV table ---
    flagged_df <- qs_df[qs_df\$Flagged, ]
    write.csv(flagged_df, "flagged_samples.csv", row.names = FALSE)
    
    # --- Save the raw quality scores as an RDS object ---
    saveRDS(qs, "sample_quality_scores.rds")
    
    # --- Generate a PDF plot of the quality scores ---
    pdf("sample_quality_plot.pdf", width = 8, height = 6)
    plot(qs, type = "h", lwd = 2, col = ifelse(qs < -5, "red", "blue"),
         main = "Sample Quality Scores (SNAGEE)",
         xlab = "Sample Index", ylab = "Quality Score (relative SNR)")
    abline(h = -5, col = "darkred", lty = 2, lwd = 2)
    legend("bottomleft", legend = c("OK", "Flagged (< -5)"),
           col = c("blue", "red"), lwd = 2)
    dev.off()

    writeLines(c(
        '"BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT":',
        paste0('    SNAGEE: ', as.character(packageVersion('SNAGEE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sample_quality_assessment.csv versions.yml
    """
}

workflow BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ALL ] ]

    main:
    BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT(ch_input)

    emit:
    tables   = BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT.out.tables
    plots    = BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT.out.plots
    objects  = BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT.out.objects
    versions = BIOC_SNAGEE_SAMPLE_QUALITY_ASSESSMENT.out.versions
}
