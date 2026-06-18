#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rsubread — single_cell_rna_seq_quantification
// Align and quantify 10x Genomics single-cell RNA-seq data to produce a UMI count matrix.
// Input: hg38_chr1.fa.gz, reads_R1.fastq.gz, reads_R2.fastq.gz
// Container: quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0
// R packages: Rsubread
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0"

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
    .bm_deps <- c("Rsubread")
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
    
    # Load the required library
    library(Rsubread)
    
    # Define input file paths (expected in the working directory)
    ref_fasta <- "hg38_chr1.fa.gz"
    reads_r1 <- "reads_R1.fastq.gz"
    reads_r2 <- "reads_R2.fastq.gz"
    
    # Verify that the input files exist
    if (!file.exists(ref_fasta)) {
      stop(paste("Required reference file missing:", ref_fasta))
    }
    if (!file.exists(reads_r1)) {
      stop(paste("Required read R1 file missing:", reads_r1))
    }
    if (!file.exists(reads_r2)) {
      stop(paste("Required read R2 file missing:", reads_r2))
    }
    
    # --- Build reference genome index using buildindex ---
    buildindex("chr1", ref_fasta)
    
    # --- Define sample sheet with barcode/UMI and read files ---
    sample.sheet <- data.frame(
      BarcodeUMIFile = reads_r1,
      ReadFile = reads_r2,
      SampleName = "Example",
      stringsAsFactors = FALSE
    )
    
    # --- Quantify single-cell expression using cellCounts ---
    counts <- cellCounts("chr1", sample.sheet, nthreads = 1, input.mode = "FASTQ", annot.inbuilt = "hg38")
    
    # Save the meaningful results to output files
    # 1. Save the complete counts list object as an RDS file
    saveRDS(counts, "cellCounts_output.rds")
    
    # 2. Save the sample information summary table as a CSV file
    if (!is.null(counts\$sample.info)) {
      write.csv(counts\$sample.info, "sample_info.csv", row.names = FALSE)
    }
    
    # 3. Save the UMI count matrix for the "Example" sample as a CSV file
    if (!is.null(counts\$counts\$Example)) {
      write.csv(as.matrix(counts\$counts\$Example), "umi_counts_matrix.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION":',
        paste0('        rsubread: ', as.character(packageVersion("rsubread")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_rna_seq_quantification.csv versions.yml
    """
}

workflow BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg38_chr1.fa.gz, reads_R1.fastq.gz, reads_R2.fastq.gz ] ]

    main:
    BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION.out.tables
    plots    = BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION.out.plots
    objects  = BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION.out.objects
    versions = BIOC_RSUBREAD_SINGLE_CELL_RNA_SEQ_QUANTIFICATION.out.versions
}
