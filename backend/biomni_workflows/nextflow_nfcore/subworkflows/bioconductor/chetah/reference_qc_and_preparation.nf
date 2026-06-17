#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CHETAH — reference_qc_and_preparation
// Prepare and evaluate the quality of a reference dataset to ensure optimal cell type classification performance.
// Input: headneck_ref, ribosomal.txt
// Container: quay.io/biocontainers/bioconductor-chetah:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CHETAH, SingleCellExperiment, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize the reference counts
//  * 2. [Core Analysis] Filter out highly expressed housekeeping/ribosomal genes
//  * 3. [Core Analysis] Correlate reference cell types using CorrelateReference to check distinguishability
//  * 4. [Core Analysis] Perform self-classification of the reference using ClassifyReference to identify potential mix-ups

nextflow.enable.dsl = 2

process BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION {
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
    .bm_deps <- c("CHETAH", "SummarizedExperiment")
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
        library(CHETAH)
        library(SummarizedExperiment)
        
        # 1. Read User Inputs from the working directory
        if (file.exists("headneck_ref")) {
          headneck_ref <- readRDS("headneck_ref")
        } else if (file.exists("headneck_ref.rds")) {
          headneck_ref <- readRDS("headneck_ref.rds")
        } else {
          stop("Error: Reference file 'headneck_ref' or 'headneck_ref.rds' not found in the working directory.")
        }
        
        if (file.exists("ribosomal.txt")) {
          ribo <- read.table("ribosomal.txt", header = FALSE, sep = '\t')
        } else {
          stop("Error: Ribosomal gene list 'ribosomal.txt' not found in the working directory.")
        }
        
        # 2. Normalize the reference counts
        assay(headneck_ref, "counts") <- apply(assay(headneck_ref, "counts"), 2, function(column) log2((column/sum(column) * 100000) + 1))
        
        # 3. Filter out highly expressed housekeeping/ribosomal genes
        headneck_ref <- headneck_ref[!rownames(headneck_ref) %in% ribo[,1], ]
        
        # 4. Correlate reference cell types to check distinguishability
        pdf("reference_correlation.pdf", width = 10, height = 8)
        print(CorrelateReference(ref_cells = headneck_ref))
        dev.off()
        
        # 5. Perform self-classification of the reference to identify potential mix-ups
        pdf("reference_self_classification.pdf", width = 10, height = 8)
        print(ClassifyReference(ref_cells = headneck_ref))
        dev.off()
        
        # 6. Save the prepared reference dataset
        saveRDS(headneck_ref, "prepared_headneck_ref.rds")

    writeLines(c(
        '"BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION":',
        paste0('    CHETAH: ', as.character(packageVersion('CHETAH')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_qc_and_preparation.csv versions.yml
    """
}

workflow BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ headneck_ref, ribosomal.txt ] ]

    main:
    BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION(ch_input)

    emit:
    tables   = BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION.out.tables
    plots    = BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION.out.plots
    objects  = BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION.out.objects
    versions = BIOC_CHETAH_REFERENCE_QC_AND_PREPARATION.out.versions
}
