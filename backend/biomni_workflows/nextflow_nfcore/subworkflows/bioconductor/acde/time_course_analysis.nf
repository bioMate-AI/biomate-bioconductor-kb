#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: acde — time_course_analysis
// Analyze gene expression changes across multiple sequential time points using active vs. supplementary time points and group conformation through time.
// Input: phytophthora, desPI
// Container: quay.io/biocontainers/bioconductor-acde:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: acde
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare a list of expression matrices and a corresponding
//  * 2. [Visualization & Output] Run the time course analysis using tc
//  * 3. [Visualization & Output] Summarize the time course results (inertia ratios, active
//  * 4. [Visualization & Output] Visualize the results across time points using plot

nextflow.enable.dsl = 2

process BIOC_ACDE_TIME_COURSE_ANALYSIS {
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
    
    # Load the required package
    library(acde)
    
    # --- Prepare a list of expression matrices and a corresponding ---
    # Read the declared USER INPUT files from the working directory.
    if (file.exists("phytophthora.rds")) {
      phytophthora <- readRDS("phytophthora.rds")
    } else if (file.exists("phytophthora.RData")) {
      load("phytophthora.RData")
    } else {
      stop("Error: 'phytophthora' input file not found in the working directory.")
    }
    
    if (file.exists("desPI.rds")) {
      desPI <- readRDS("desPI.rds")
    } else if (file.exists("desPI.RData")) {
      load("desPI.RData")
    } else {
      stop("Error: 'desPI' input file not found in the working directory.")
    }
    
    # --- Run the time course analysis using tc ---
    # Keep the documented function call and its argument names EXACTLY as shown in the vignette.
    tcPI <- tc(phytophthora, desPI)
    
    # --- Summarize the time course results (inertia ratios, active ---
    # using summary and print the object.
    summary_stats <- summary(tcPI)
    print(summary_stats)
    print(tcPI)
    
    # Save the text summary and print outputs to a file
    sink("tcPI_summary_output.txt")
    cat("=== TIME COURSE ANALYSIS SUMMARY ===\n")
    print(summary_stats)
    cat("\n=== TIME COURSE ANALYSIS DETAILS ===\n")
    print(tcPI)
    sink()
    
    # --- Visualize the results across time points using plot ---
    # Save the generated plots to a PDF file
    pdf("tcPI_plots.pdf", width = 10, height = 8)
    plot(tcPI)
    dev.off()
    
    # Save the meaningful results as an RDS object
    saveRDS(tcPI, "tcPI_results.rds")
    
    # Safely export tabular results to CSV if available
    tryCatch({
      if (!is.null(tcPI\$act) && !is.null(tcPI\$act\$dgenes)) {
        write.csv(as.data.frame(tcPI\$act\$dgenes), "active_timepoint_dgenes.csv", row.names = TRUE)
      }
    }, error = function(e) {
      warning("Could not export active timepoint gene classifications to CSV.")
    })
    
    tryCatch({
      if (!is.null(tcPI\$gct) && is.matrix(tcPI\$gct)) {
        write.csv(as.data.frame(tcPI\$gct), "groups_conformation_matrix.csv", row.names = TRUE)
      }
    }, error = function(e) {
      warning("Could not export groups conformation matrix to CSV.")
    })

    writeLines(c(
        '"BIOC_ACDE_TIME_COURSE_ANALYSIS":',
        paste0('    acde: ', as.character(packageVersion('acde')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_course_analysis.csv versions.yml
    """
}

workflow BIOC_ACDE_TIME_COURSE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phytophthora, desPI ] ]

    main:
    BIOC_ACDE_TIME_COURSE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ACDE_TIME_COURSE_ANALYSIS.out.tables
    plots    = BIOC_ACDE_TIME_COURSE_ANALYSIS.out.plots
    objects  = BIOC_ACDE_TIME_COURSE_ANALYSIS.out.objects
    versions = BIOC_ACDE_TIME_COURSE_ANALYSIS.out.versions
}
