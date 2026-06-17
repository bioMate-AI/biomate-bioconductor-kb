#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaseqR2 — combine_p_values
// Combine p-values from multiple statistical algorithms using Simes, Harmonic Mean, or PANDORA weighting methods.
// Input: hg19pvalues
// Container: quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0
// R packages: metaseqR2
// Bioconductor: 3.20 | R: 4.4
// Requires: metaseqR2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load p-value matrix
//  * 2. [Core Analysis] Combine using combineSimes
//  * 3. [Core Analysis] Retrieve weights using getWeights
//  * 4. [Core Analysis] Combine using combineHarmonic or combineWeight

nextflow.enable.dsl = 2

process BIOC_METASEQR2_COMBINE_P_VALUES {
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
    .bm_deps <- c("metaseqR2")
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
    library(metaseqR2)
    
    # 1. Load p-value matrix from the working directory
    # The pipeline expects 'hg19pvalues' as a CSV, TSV, TXT, or RDS file.
    if (file.exists("hg19pvalues.csv")) {
      hg19pvalues <- read.csv("hg19pvalues.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("hg19pvalues.tsv")) {
      hg19pvalues <- read.delim("hg19pvalues.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("hg19pvalues.txt")) {
      hg19pvalues <- read.delim("hg19pvalues.txt", row.names = 1, check.names = FALSE)
    } else if (file.exists("hg19pvalues.rds")) {
      hg19pvalues <- readRDS("hg19pvalues.rds")
    } else if (file.exists("hg19pvalues")) {
      hg19pvalues <- tryCatch({
        read.table("hg19pvalues", header = TRUE, row.names = 1, check.names = FALSE)
      }, error = function(e) {
        readRDS("hg19pvalues")
      })
    } else {
      stop("Required input file 'hg19pvalues' (CSV, TSV, TXT, or RDS) not found in the working directory.")
    }
    
    # Convert to matrix if it's not already, ensuring numeric values
    hg19pvalues <- as.matrix(hg19pvalues)
    
    # Examine the data
    head(hg19pvalues)
    
    # 2. Combine the p-values using the Simes method
    pSimes <- apply(hg19pvalues,1,combineSimes)
    
    # 3. Retrieve weights using getWeights
    w <- getWeights("human")
    
    # 4. Combine using the harmonic mean method with PANDORA weights
    pHarm <- apply(hg19pvalues,1,combineHarmonic,w)
    
    # 5. Combine using the PANDORA method
    pPandora <- apply(hg19pvalues,1,combineWeight,w)
    
    # Create a consolidated data frame of the results
    combined_results <- data.frame(
      Simes = pSimes,
      HarmonicMean = pHarm,
      Pandora = pPandora,
      row.names = rownames(hg19pvalues)
    )
    
    # Write named output files for the meaningful results
    write.csv(combined_results, file = "combined_pvalues.csv", row.names = TRUE)
    saveRDS(combined_results, file = "combined_pvalues.rds")
    
    # Generate a diagnostic plot comparing the combined p-value distributions
    pdf("combined_pvalues_distribution.pdf", width = 8, height = 6)
    op <- par(mfrow = c(3, 1), mar = c(4, 4, 2, 1))
    hist(pSimes, breaks = 50, col = "skyblue", main = "Simes Method", xlab = "p-value")
    hist(pHarm, breaks = 50, col = "lightgreen", main = "Harmonic Mean Method", xlab = "p-value")
    hist(pPandora, breaks = 50, col = "salmon", main = "PANDORA Method", xlab = "p-value")
    par(op)
    dev.off()
    
    cat("Workflow completed successfully. Outputs written to 'combined_pvalues.csv', 'combined_pvalues.rds', and 'combined_pvalues_distribution.pdf'.\n")

    writeLines(c(
        '"BIOC_METASEQR2_COMBINE_P_VALUES":',
        paste0('    metaseqR2: ', as.character(packageVersion('metaseqR2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_combine_p_values.csv versions.yml
    """
}

workflow BIOC_METASEQR2_COMBINE_P_VALUES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg19pvalues ] ]

    main:
    BIOC_METASEQR2_COMBINE_P_VALUES(ch_input)

    emit:
    tables   = BIOC_METASEQR2_COMBINE_P_VALUES.out.tables
    plots    = BIOC_METASEQR2_COMBINE_P_VALUES.out.plots
    objects  = BIOC_METASEQR2_COMBINE_P_VALUES.out.objects
    versions = BIOC_METASEQR2_COMBINE_P_VALUES.out.versions
}
