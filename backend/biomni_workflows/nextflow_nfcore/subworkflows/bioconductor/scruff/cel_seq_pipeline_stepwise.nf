#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scruff — cel_seq_pipeline_stepwise
// Run stepwise demultiplexing, alignment, and UMI counting for CEL-Seq/CEL-Seq2 data.
// Input: read1Path.fastq.gz, read2Path.fastq.gz, reference.fa, reference.gtf, barcode_list.tsv
// Container: quay.io/biocontainers/bioconductor-scruff:1.28.0--r45hdfd78af_0
// R packages: patchwork, scruff
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE {
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
    .bm_deps <- c("patchwork", "scruff")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    
    # Define input file paths from the working directory
    v1h1R1 <- "read1Path.fastq.gz"
    v1h1R2 <- "read2Path.fastq.gz"
    fasta <- "reference.fa"
    gtf <- "reference.gtf"
    barcode_file <- "barcode_list.tsv"
    
    # Read predefined cell barcodes from the user-provided TSV file
    barcodeExample <- readLines(barcode_file)
    barcodeExample <- trimws(barcodeExample)
    barcodeExample <- barcodeExample[barcodeExample != ""]
    
    # --- Demultiplex reads using demultiplex ---
    de <- demultiplex(
      project = "example",
      experiment = c("1h1"),
      lane = c("L001"),
      read1Path = c(v1h1R1),
      read2Path = c(v1h1R2),
      barcodeExample,
      bcStart = 1,
      bcStop = 8,
      bcEdit = 1,
      umiStart = 9,
      umiStop = 12,
      keep = 75,
      minQual = 10,
      yieldReads = 1e+06,
      verbose = TRUE,
      overwrite = TRUE,
      cores = 2
    )
    
    # Save demultiplexing intermediate results
    saveRDS(de, "demultiplex_results.rds")
    
    # --- Build Rsubread index ---
    indexBase <- "reference_index"
    Rsubread::buildindex(
      basename = indexBase,
      reference = fasta,
      indexSplit = FALSE
    )
    
    # --- Align reads using alignRsubread ---
    al <- alignRsubread(
      de,
      indexBase,
      unique = FALSE,
      nBestLocations = 1,
      format = "BAM",
      overwrite = TRUE,
      verbose = TRUE,
      cores = 2
    )
    
    # Save alignment intermediate results
    saveRDS(al, "alignment_results.rds")
    
    # --- Count UMIs using countUMI ---
    # Dynamically construct cellPerWell vector to match the length of the input barcode list
    num_barcodes <- length(barcodeExample)
    num_ones <- max(0, num_barcodes - 2)
    num_zeros <- min(2, num_barcodes)
    cellPerWellVal <- c(rep(1, num_ones), rep(0, num_zeros))
    
    sce <- countUMI(
      al,
      gtf,
      umiEdit = 1,
      format = "BAM",
      cellPerWell = cellPerWellVal,
      verbose = TRUE,
      cores = 2
    )
    
    # Save the SingleCellExperiment object and count matrix
    saveRDS(sce, "scruff_sce.rds")
    write.csv(as.matrix(SingleCellExperiment::counts(sce)), "umi_counts.csv", row.names = TRUE)
    
    # --- Plot QC metrics ---
    qc <- qcplots(sce)
    
    # Save QC plots to PDF
    pdf("qc_plots.pdf", width = 12, height = 8)
    print(qc)
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE":',
        paste0('        scruff: ', as.character(packageVersion("scruff")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cel_seq_pipeline_stepwise.csv versions.yml
    """
}

workflow BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ read1Path.fastq.gz, read2Path.fastq.gz, reference.fa, reference.gtf, barcode_list.tsv ] ]

    main:
    BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE(ch_input)

    emit:
    tables   = BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE.out.tables
    plots    = BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE.out.plots
    objects  = BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE.out.objects
    versions = BIOC_SCRUFF_CEL_SEQ_PIPELINE_STEPWISE.out.versions
}
