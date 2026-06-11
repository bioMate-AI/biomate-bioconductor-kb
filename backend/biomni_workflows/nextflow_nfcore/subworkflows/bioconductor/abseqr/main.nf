#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: abseqr — basic_and_comparative_report
// Generate individual and comparative quality, abundance, productivity, and diversity reports from a single directory of abseqPy outputs.
// Input: dataPath
// Container: quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0
// R packages: BiocParallel, abseqR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("BiocParallel", "abseqR")
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
    library(abseqR)
    library(BiocParallel)
    
    # Define user input path
    dataPath <- "dataPath"
    
    # Validate input directory
    if (!dir.exists(dataPath)) {
        stop(paste("Error: Input directory 'dataPath' does not exist at:", normalizePath(dataPath, mustWork = FALSE)))
    }
    
    # --- Configure parallelization parameters based on the ---
    if (Sys.info()["sysname"] == "Darwin") {
        BPPARAM <- BiocParallel::SerialParam()
    } else {
        BPPARAM <- BiocParallel::bpparam()
    }
    
    # --- Run abseqReport to generate static/interactive plots and ---
    # for individual samples and specified comparative groups.
    samples <- abseqReport(dataPath,
                           compare = c("PCR1, PCR2, PCR3"),
                           report = 1,
                           BPPARAM = BPPARAM)
    
    # Save the resulting S4 object to an RDS file
    saveRDS(samples, file = "abseq_samples.rds")

    writeLines(c(
        '"BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT":',
        paste0('        abseqr: ', as.character(packageVersion("abseqr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_basic_and_comparative_report.csv versions.yml
    """
}

workflow BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataPath ] ]

    main:
    BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT(ch_input)

    emit:
    tables   = BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT.out.tables
    plots    = BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT.out.plots
    objects  = BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT.out.objects
    versions = BIOC_ABSEQR_BASIC_AND_COMPARATIVE_REPORT.out.versions
}
