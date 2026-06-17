#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rsubread — single_cell_10x_quantification
// Align and quantify 10x Genomics single-cell RNA-seq data to produce a UMI count matrix.
// Input: hg38_chr1.fa.gz, reads_R1.fastq.gz, reads_R2.fastq.gz
// Container: quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0
// R packages: Rsubread
// Bioconductor: 3.20 | R: 4.4
// Requires: Rsubread
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build reference index using buildindex
//  * 2. [Input & Preparation] Define sample sheet with Barcode/UMI and Read files
//  * 3. [Core Analysis] Run single-cell quantification using cellCounts

nextflow.enable.dsl = 2

process BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION {
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
    .bm_deps <- c("Rsubread")
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
    library(Rsubread)
    
    # Define local file paths as specified by user input
    ref_fasta <- "hg38_chr1.fa.gz"
    barcode_umi_file <- "reads_R1.fastq.gz"
    read_file <- "reads_R2.fastq.gz"
    
    # Verify input files exist in the working directory
    if (!file.exists(ref_fasta)) {
      stop(paste("Required input file missing:", ref_fasta))
    }
    if (!file.exists(barcode_umi_file)) {
      stop(paste("Required input file missing:", barcode_umi_file))
    }
    if (!file.exists(read_file)) {
      stop(paste("Required input file missing:", read_file))
    }
    
    # Stage 1: Build reference index using buildindex
    # Replicates: buildindex(paste0(temp.dir,"/chr1"), paste0(temp.dir,"/cellCounts-Example/hg38_chr1.fa.gz"))
    buildindex("chr1", ref_fasta)
    
    # Stage 2: Define sample sheet with Barcode/UMI and Read files
    # Replicates the documented sample.sheet structure
    sample.sheet <- data.frame(
      BarcodeUMIFile = barcode_umi_file, 
      ReadFile = read_file,
      SampleName="Example", stringsAsFactors=FALSE
    )
    
    # Stage 3: Run single-cell quantification using cellCounts
    # Replicates: counts <- cellCounts(paste0(temp.dir,"/chr1"), sample.sheet,  nthreads=1, input.mode="FASTQ", annot.inbuilt="hg38")
    counts <- cellCounts("chr1", sample.sheet,  nthreads=1,
      input.mode="FASTQ", annot.inbuilt="hg38")
    
    # Print documented outputs to standard output
    print(counts\$sample.info)
    print(dim(counts\$counts\$Example))
    
    # Write meaningful results to output files
    write.csv(counts\$sample.info, "cellCounts_sample_info.csv", row.names = FALSE)
    saveRDS(counts, "cellCounts_output.rds")
    
    # Export the UMI count matrix for the "Example" sample
    if (!is.null(counts\$counts\$Example)) {
      saveRDS(counts\$counts\$Example, "cellCounts_matrix_Example.rds")
      # Convert to standard matrix if it is a sparse matrix class to write to CSV
      write.csv(as.matrix(counts\$counts\$Example), "cellCounts_matrix_Example.csv")
    }

    writeLines(c(
        '"BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION":',
        paste0('    Rsubread: ', as.character(packageVersion('Rsubread')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_10x_quantification.csv versions.yml
    """
}

workflow BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg38_chr1.fa.gz, reads_R1.fastq.gz, reads_R2.fastq.gz ] ]

    main:
    BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION.out.tables
    plots    = BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION.out.plots
    objects  = BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION.out.objects
    versions = BIOC_RSUBREAD_SINGLE_CELL_10X_QUANTIFICATION.out.versions
}
