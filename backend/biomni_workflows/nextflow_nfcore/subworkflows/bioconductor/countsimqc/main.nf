#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: countsimQC — count_dataset_comparison
// Compare characteristic features across multiple count datasets, generate a comprehensive HTML/PDF report, and export individual figures.
// Input: countsimExample
// Container: quay.io/biocontainers/bioconductor-countsimqc:1.28.0--r45hdfd78af_0
// R packages: countsimQC, DESeq2
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, countsimQC
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the countsimQC and DESeq2 libraries. 2. Prepare the input datasets as a named list of DESeqDataSet, matrix, or data.frame obj

nextflow.enable.dsl = 2

process BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON {
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
    .bm_deps <- c("countsimQC", "DESeq2")
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
    
    suppressPackageStartupMessages({
      library(countsimQC)
      library(DESeq2)
    })
    
    # Read user input from the working directory
    if (file.exists("countsimExample.rds")) {
      countsimExample <- readRDS("countsimExample.rds")
    } else if (file.exists("countsimExample")) {
      countsimExample <- tryCatch({
        readRDS("countsimExample")
      }, error = function(e) {
        env <- new.env()
        load("countsimExample", envir = env)
        env[[names(env)[1]]]
      })
    } else {
      stop("Required input file 'countsimExample' (RDS format) not found in the working directory.")
    }
    
    # Prepare the input datasets by subsetting features
    countsimExample <- lapply(countsimExample, function(cse) {
      cse[seq_len(min(1500, nrow(cse))), ]
    })
    
    # Run countsimQCReport to perform statistical comparisons and generate the HTML report
    tempDir <- tempdir()
    countsimQCReport(ddsList = countsimExample, outputFile = "countsim_report.html",
                     outputDir = tempDir, outputFormat = "html_document", 
                     showCode = FALSE, forceOverwrite = TRUE,
                     savePlots = TRUE, description = "This is my test report.", 
                     maxNForCorr = 25, maxNForDisp = Inf, 
                     calculateStatistics = TRUE, subsampleSize = 25,
                     kfrac = 0.01, kmin = 5, 
                     permutationPvalues = FALSE, nPermutations = NULL)
    
    # Read the saved ggplot objects from the generated RDS file and export individual figures
    ggplots <- readRDS(file.path(tempDir, "countsim_report_ggplots.rds"))
    if (!dir.exists(file.path(tempDir, "figures"))) {
      dir.create(file.path(tempDir, "figures"))
    }
    generateIndividualPlots(ggplots, device = "pdf", nDatasets = length(countsimExample), 
                            outputDir = file.path(tempDir, "figures"))
    
    # Copy final outputs to the working directory
    file.copy(file.path(tempDir, "countsim_report.html"), "./countsim_report.html", overwrite = TRUE)
    file.copy(file.path(tempDir, "countsim_report_ggplots.rds"), "./countsim_report_ggplots.rds", overwrite = TRUE)
    if (dir.exists(file.path(tempDir, "figures"))) {
      if (!dir.exists("figures")) {
        dir.create("figures")
      }
      file.copy(list.files(file.path(tempDir, "figures"), full.names = TRUE), "figures", overwrite = TRUE)
    }

    writeLines(c(
        '"BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON":',
        paste0('    countsimQC: ', as.character(packageVersion('countsimQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_count_dataset_comparison.csv versions.yml
    """
}

workflow BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ countsimExample ] ]

    main:
    BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON(ch_input)

    emit:
    tables   = BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON.out.tables
    plots    = BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON.out.plots
    objects  = BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON.out.objects
    versions = BIOC_COUNTSIMQC_COUNT_DATASET_COMPARISON.out.versions
}
