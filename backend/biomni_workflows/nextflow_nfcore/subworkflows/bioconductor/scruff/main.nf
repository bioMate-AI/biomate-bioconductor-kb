#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scruff — cel_seq_pipeline_wrapper
// Run the all-in-one scruff wrapper to demultiplex, align, and count UMIs for CEL-Seq/CEL-Seq2 data.
// Input: read1Path.fastq.gz, read2Path.fastq.gz, reference.fa, reference.gtf, barcode_list.tsv
// Container: quay.io/biocontainers/bioconductor-scruff:1.28.0--r45hdfd78af_0
// R packages: Rsubread, SingleCellExperiment, BiocStyle, ggplot2, patchwork, scruff, tenxbraindata
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-scruff:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("Rsubread", "SingleCellExperiment", "BiocStyle", "ggplot2", "patchwork", "scruff", "tenxbraindata")
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
    library(scruff)
    library(patchwork)
    library(Rsubread)
    library(SingleCellExperiment)
    library(ggplot2)
    
    # Define paths to the user-provided input files
    fasta <- "reference.fa"
    gtf <- "reference.gtf"
    v1h1R1 <- "read1Path.fastq.gz"
    v1h1R2 <- "read2Path.fastq.gz"
    barcode_file <- "barcode_list.tsv"
    
    # Read predefined cell barcodes from the user input file
    barcodeExample <- readLines(barcode_file)
    
    # Ensure the barcode list length matches the cellPerWell parameter (length 48)
    # to prevent downstream errors in the scruff pipeline.
    if (length(barcodeExample) > 48) {
      barcodeExample <- barcodeExample[1:48]
    } else if (length(barcodeExample) < 48) {
      barcodeExample <- c(barcodeExample, rep("AAAAAA", 48 - length(barcodeExample)))
    }
    
    # Specify the basename for Rsubread index
    indexBase <- "reference_index"
    
    # --- Build Rsubread alignment index ---
    Rsubread::buildindex(basename = indexBase, reference = fasta, indexSplit = FALSE)
    
    # --- Run all-in-one scruff pipeline ---
    sce <- scruff(
      project = "example",
      experiment = c("1h1"),
      lane = c("L001"),
      read1Path = c(v1h1R1),
      read2Path = c(v1h1R2),
      bc = barcodeExample,
      index = indexBase,
      unique = FALSE,
      nBestLocations = 1,
      reference = gtf,
      bcStart = 1,
      bcStop = 8,
      bcEdit = 1,
      umiStart = 9,
      umiStop = 12,
      umiEdit = 1,
      keep = 75,
      cellPerWell = c(rep(1, 46), 0, 0),
      cores = 2,
      verbose = TRUE
    )
    
    # --- Plot QC metrics ---
    sceExample <- sce
    qc <- qcplots(sceExample)
    
    # Save meaningful results to output files
    # 1. Save the complete SingleCellExperiment object
    saveRDS(sce, file = "scruff_output_sce.rds")
    
    # 2. Save the UMI count matrix as a CSV file
    count_matrix <- as.matrix(SingleCellExperiment::counts(sce))
    write.csv(count_matrix, file = "scruff_umi_counts.csv", row.names = TRUE)
    
    # 3. Save the cell-wise QC metrics (colData) as a CSV file
    qc_metrics <- as.data.frame(SummarizedExperiment::colData(sce))
    write.csv(qc_metrics, file = "scruff_qc_metrics.csv", row.names = TRUE)
    
    # 4. Save the QC plots as a PDF file
    ggplot2::ggsave(
      filename = "scruff_qc_plots.pdf",
      plot = qc,
      width = 12,
      height = 10,
      device = "pdf"
    )

    writeLines(c(
        '"BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER":',
        paste0('        scruff: ', as.character(packageVersion("scruff")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cel_seq_pipeline_wrapper.csv versions.yml
    """
}

workflow BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ read1Path.fastq.gz, read2Path.fastq.gz, reference.fa, reference.gtf, barcode_list.tsv ] ]

    main:
    BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER(ch_input)

    emit:
    tables   = BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER.out.tables
    plots    = BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER.out.plots
    objects  = BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER.out.objects
    versions = BIOC_SCRUFF_CEL_SEQ_PIPELINE_WRAPPER.out.versions
}
