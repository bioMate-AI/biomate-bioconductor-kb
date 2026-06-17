#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: simPIC — pic_matrix_generation
// Generate a Paired-Insertion Count (PIC) matrix from raw single-cell ATAC-seq files.
// Input: singlecell.csv, peaks.bed, fragment.tsv.gz
// Container: quay.io/biocontainers/bioconductor-simpic:1.6.0--r45hdfd78af_0
// R packages: GenomicRanges, IRanges, simPIC
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, simPIC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read cell barcodes and metadata
//  * 2. [Core Analysis] Read peak regions and convert to a GRanges object
//  * 3. [Core Analysis] Run PIC counting to generate the PIC matrix
//  * 4. [Core Analysis] Save the resulting PIC matrix and write outputs

nextflow.enable.dsl = 2

process BIOC_SIMPIC_PIC_MATRIX_GENERATION {
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
    .bm_deps <- c("GenomicRanges", "IRanges", "simPIC")
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
    library(simPIC)
    library(GenomicRanges)
    
    # Define input file paths as specified by the user
    cells_file <- "singlecell.csv"
    peaks_file <- "peaks.bed"
    fragment_tsv_gz_file_location <- "fragment.tsv.gz"
    
    # Verify that the required input files exist
    if (!file.exists(cells_file)) {
        stop(paste("Required input file missing:", cells_file))
    }
    if (!file.exists(peaks_file)) {
        stop(paste("Required input file missing:", peaks_file))
    }
    if (!file.exists(fragment_tsv_gz_file_location)) {
        stop(paste("Required input file missing:", fragment_tsv_gz_file_location))
    }
    
    # --- Read cell barcodes and metadata ---
    # Typically, cells can be represented as a data frame or a vector of barcodes.
    # We read the CSV file directly.
    cells <- read.csv(cells_file, stringsAsFactors = FALSE)
    
    # --- Read peak regions and convert to a GRanges object ---
    # BED files are tab-separated with chromosome, start, and end in the first three columns.
    peaks_df <- read.table(peaks_file, header = FALSE, sep = "\t", stringsAsFactors = FALSE)
    colnames(peaks_df)[1:3] <- c("chrom", "start", "end")
    
    peak_sets <- GenomicRanges::GRanges(
        seqnames = peaks_df\$chrom,
        ranges = IRanges::IRanges(start = peaks_df\$start, end = peaks_df\$end)
    )
    
    # --- Run PIC counting to generate the PIC matrix ---
    message("Running PIC_counting to generate the Paired-Insertion Count (PIC) matrix...")
    pic_mat <- PIC_counting(
        cells = cells,
        fragment_tsv_gz_file_location = fragment_tsv_gz_file_location,
        peak_sets = peak_sets
    )
    
    # --- Save the resulting PIC matrix and write outputs ---
    output_rds <- "pic_matrix.rds"
    saveRDS(pic_mat, file = output_rds)
    message(paste("Successfully saved PIC matrix to", output_rds))
    
    # Write a quick summary log of the generated matrix
    output_summary <- "pic_matrix_summary.txt"
    sink(output_summary)
    cat("=== PIC Matrix Summary ===\n")
    cat("Dimensions:\n")
    print(dim(pic_mat))
    cat("\nClass:\n")
    print(class(pic_mat))
    sink()
    message(paste("Summary written to", output_summary))

    writeLines(c(
        '"BIOC_SIMPIC_PIC_MATRIX_GENERATION":',
        paste0('    simPIC: ', as.character(packageVersion('simPIC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pic_matrix_generation.csv versions.yml
    """
}

workflow BIOC_SIMPIC_PIC_MATRIX_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ singlecell.csv, peaks.bed, fragment.tsv.gz ] ]

    main:
    BIOC_SIMPIC_PIC_MATRIX_GENERATION(ch_input)

    emit:
    tables   = BIOC_SIMPIC_PIC_MATRIX_GENERATION.out.tables
    plots    = BIOC_SIMPIC_PIC_MATRIX_GENERATION.out.plots
    objects  = BIOC_SIMPIC_PIC_MATRIX_GENERATION.out.objects
    versions = BIOC_SIMPIC_PIC_MATRIX_GENERATION.out.versions
}
