#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MassArray — massarray_data_analysis
// Import EpiTyper data, perform quality control, visualize methylation levels, and detect potential SNPs.
// Input: Example.txt, sequence
// Container: quay.io/biocontainers/bioconductor-massarray:1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MassArray
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files from the working directory
//  * 2. [Visualization & Output] Import EpiTyper data and sequence into a MassArrayData
//  * 3. [Visualization & Output] Visualize methylation levels and save to a PDF file
//  * 4. [Visualization & Output] Evaluate potential SNPs

nextflow.enable.dsl = 2

process BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("MassArray")
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
    
    # Load required library
    library(MassArray)
    
    # --- Read user input files from the working directory ---
    if (!file.exists("sequence")) {
      stop("Error: Required input file 'sequence' not found in the working directory.")
    }
    if (!file.exists("Example.txt")) {
      stop("Error: Required input file 'Example.txt' not found in the working directory.")
    }
    
    # Read and clean the amplicon sequence string
    sequence_lines <- readLines("sequence", warn = FALSE)
    sequence <- paste(sequence_lines, collapse = "")
    sequence <- gsub("[ \t\r\n]", "", sequence)
    
    # --- Import EpiTyper data and sequence into a MassArrayData ---
    data <- new("MassArrayData", sequence, file = "Example.txt")
    
    # --- Visualize methylation levels and save to a PDF file ---
    pdf("methylation_plots.pdf", width = 11, height = 8.5)
    plot(data, collapse = FALSE, bars = FALSE, scale = FALSE)
    plot(data, collapse = TRUE, bars = TRUE, scale = FALSE)
    plot(data, collapse = TRUE, bars = FALSE, scale = TRUE)
    dev.off()
    
    # --- Evaluate potential SNPs ---
    SNP.results <- evaluateSNPs(data)
    
    # Save the complete SNP results object
    saveRDS(SNP.results, file = "SNP_results.rds")
    
    # Write a text summary of the SNP results
    sink("SNP_results_summary.txt")
    cat("=== SNP Evaluation Summary ===\n")
    cat("Total potential SNPs detected:", length(SNP.results), "\n\n")
    if (length(SNP.results) >= 2) {
      cat("Details for SNP Result [[2]]:\n")
      print(SNP.results[[2]])
    } else if (length(SNP.results) > 0) {
      cat("Details for SNP Result [[1]]:\n")
      print(SNP.results[[1]])
    } else {
      cat("No potential SNPs detected.\n")
    }
    sink()

    writeLines(c(
        '"BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS":',
        paste0('    MassArray: ', as.character(packageVersion('MassArray')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_massarray_data_analysis.csv versions.yml
    """
}

workflow BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Example.txt, sequence ] ]

    main:
    BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.tables
    plots    = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.plots
    objects  = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.objects
    versions = BIOC_MASSARRAY_MASSARRAY_DATA_ANALYSIS.out.versions
}
