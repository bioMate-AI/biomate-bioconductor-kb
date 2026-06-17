#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scmeth — comprehensive_qc_report
// Generate an all-inclusive HTML quality control report for a methylation dataset.
// Input: directory
// Container: quay.io/biocontainers/bioconductor-scmeth:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg38, HDF5Array, scmeth
// QC: array detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the bsseq object from the HDF5 directory
//  * 2. [Visualization & Output] Generate the HTML quality control report using the report function

nextflow.enable.dsl = 2

process BIOC_SCMETH_COMPREHENSIVE_QC_REPORT {
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
    .bm_deps <- c("scmeth", "HDF5Array", "BSgenome.Hsapiens.UCSC.hg38")
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
    library(scmeth)
    library(HDF5Array)
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Define input directory containing the HDF5-stored bsseq object
    # The pipeline reads the 'directory' folder from the working directory
    directory <- "directory"
    
    # Check if the input directory exists
    if (!dir.exists(directory)) {
      stop(paste("Input directory '", directory, "' does not exist in the current working directory.", sep = ""))
    }
    
    # 1. Load the bsseq object from the HDF5 directory
    message("Loading HDF5 Summarized Experiment...")
    bsObject <- HDF5Array::loadHDF5SummarizedExperiment(directory)
    
    # 2. Generate the HTML quality control report using the report function
    # We use the current working directory '.' as the output directory to ensure writability
    message("Generating comprehensive QC report...")
    report(bsObject, '.', Hsapiens, "hg38")
    
    # Verify output generation
    output_report <- "qcReport.html"
    if (file.exists(output_report)) {
      message(paste("Successfully generated QC report:", output_report))
    } else {
      warning("QC report file was not found in the output directory.")
    }

    writeLines(c(
        '"BIOC_SCMETH_COMPREHENSIVE_QC_REPORT":',
        paste0('    scmeth: ', as.character(packageVersion('scmeth')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comprehensive_qc_report.csv versions.yml
    """
}

workflow BIOC_SCMETH_COMPREHENSIVE_QC_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory ] ]

    main:
    BIOC_SCMETH_COMPREHENSIVE_QC_REPORT(ch_input)

    emit:
    tables   = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.tables
    plots    = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.plots
    objects  = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.objects
    versions = BIOC_SCMETH_COMPREHENSIVE_QC_REPORT.out.versions
}
