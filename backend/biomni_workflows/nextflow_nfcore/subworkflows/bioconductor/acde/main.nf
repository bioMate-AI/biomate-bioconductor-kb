#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: acde — single_time_point_analysis
// Detect differentially expressed genes at a single experimental time point using artificial components and FDR estimation.
// Input: dat, des
// Container: quay.io/biocontainers/bioconductor-acde:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: acde
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the package and prepare the expression matrix and
//  * 2. [Visualization & Output] Run the single time point analysis using stp (enabling
//  * 3. [Visualization & Output] Print the summary of results (achieved FDR, number of
//  * 4. [Visualization & Output] Plot the estimated FDR curve and the genes on the
//  * 5. [Visualization & Output] Write named output files for the meaningful results

nextflow.enable.dsl = 2

process BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS {
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
    .bm_deps <- c("acde")
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
    
    # --- Load the package and prepare the expression matrix and ---
    library(acde)
    
    # Read the expression matrix (dat) from the working directory
    if (file.exists("dat.csv")) {
      dat <- as.matrix(read.csv("dat.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("dat.tsv")) {
      dat <- as.matrix(read.delim("dat.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("dat.txt")) {
      dat <- as.matrix(read.table("dat.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Expression matrix file (dat.csv, dat.tsv, or dat.txt) not found in the working directory.")
    }
    
    # Read the design vector (des) from the working directory
    if (file.exists("des.csv")) {
      des <- as.numeric(read.csv("des.csv", header = FALSE)[[1]])
    } else if (file.exists("des.txt")) {
      des <- scan("des.txt", what = numeric(), quiet = TRUE)
    } else {
      stop("Error: Design vector file (des.csv or des.txt) not found in the working directory.")
    }
    
    # --- Run the single time point analysis using stp (enabling ---
    stpPI <- stp(dat, des, BCa=TRUE)
    
    # --- Print the summary of results (achieved FDR, number of ---
    stpPI
    
    # --- Plot the estimated FDR curve and the genes on the ---
    # Save the default plots to a PDF file
    pdf("stp_plots.pdf", width = 7, height = 9)
    plot(stpPI)
    invisible(dev.off())
    
    # Save individual plots as described in the vignette
    golden <- 1.1 * (1 + sqrt(5)) / 2
    hi <- 4
    
    pdf("acde-plotStpFDR.pdf", width = golden * hi, height = hi)
    par(mfrow = c(1, 1), mar = c(4, 4, 1, 1), las = 1)
    plot(stpPI, AC = FALSE)
    invisible(dev.off())
    
    pdf("acde-plotStpAC.pdf", width = golden * hi, height = hi)
    par(mfrow = c(1, 1), mar = c(4, 4, 1, 1), las = 1)
    plot(stpPI, FDR = FALSE)
    invisible(dev.off())
    
    # --- Write named output files for the meaningful results ---
    # Save the complete STP object
    saveRDS(stpPI, file = "stp_results.rds")
    
    # Extract and save the results table
    results_df <- data.frame(
      psi1 = stpPI\$ac[, 1],
      psi2 = stpPI\$ac[, 2],
      qvalue = stpPI\$qvalues,
      status = stpPI\$dgenes,
      row.names = rownames(dat)
    )
    write.csv(results_df, file = "stp_results_table.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS":',
        paste0('    acde: ', as.character(packageVersion('acde')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_time_point_analysis.csv versions.yml
    """
}

workflow BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat, des ] ]

    main:
    BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS.out.tables
    plots    = BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS.out.plots
    objects  = BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS.out.objects
    versions = BIOC_ACDE_SINGLE_TIME_POINT_ANALYSIS.out.versions
}
