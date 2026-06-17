#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rbwa — bwa_mem_long_reads
// Align longer DNA sequencing reads (70bp to 1Mbp) to a reference genome using BWA-MEM, directly producing a SAM file.
// Input: reference.fa, reads.fastq
// Container: quay.io/biocontainers/bioconductor-rbwa:1.14.0--r45h01b2380_0
// R packages: Rbwa
// Bioconductor: 3.20 | R: 4.4
// Requires: Rbwa
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build reference genome index using bwa_build_index
//  * 2. [Core Analysis] Align reads directly to SAM format using bwa_mem

nextflow.enable.dsl = 2

process BIOC_RBWA_BWA_MEM_LONG_READS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("Rbwa")
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
    library(Rbwa)
    
    # Define input files from the working directory
    fasta <- "reference.fa"
    fastq <- "reads.fastq"
    
    # Validate input files
    if (!file.exists(fasta)) {
      stop("Error: Input reference genome file 'reference.fa' is missing from the working directory.")
    }
    if (!file.exists(fastq)) {
      stop("Error: Input reads file 'reads.fastq' is missing from the working directory.")
    }
    
    # Define output directory and index prefix
    dir <- "."
    index_prefix <- file.path(dir, "ref_index")
    
    # Step 1: Build reference genome index
    message("Building BWA index...")
    bwa_build_index(fasta, index_prefix=index_prefix)
    
    # Step 2: Align reads directly to SAM format using BWA-MEM
    message("Aligning reads using BWA-MEM...")
    bwa_mem(index_prefix=index_prefix,
            fastq_files=fastq,
            sam_file=file.path(dir, "output.sam"))
    
    # Verify and write a summary of the output
    sam_file_path <- file.path(dir, "output.sam")
    if (file.exists(sam_file_path)) {
      message("Alignment completed successfully. Output saved to: ", sam_file_path)
      
      # Read and save a preview of the SAM file
      sam_preview <- readLines(sam_file_path, n = 50)
      writeLines(sam_preview, "sam_preview.txt")
      message("A preview of the SAM file has been saved to 'sam_preview.txt'.")
    } else {
      stop("Error: SAM file generation failed.")
    }

    writeLines(c(
        '"BIOC_RBWA_BWA_MEM_LONG_READS":',
        paste0('    Rbwa: ', as.character(packageVersion('Rbwa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bwa_mem_long_reads.csv versions.yml
    """
}

workflow BIOC_RBWA_BWA_MEM_LONG_READS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference.fa, reads.fastq ] ]

    main:
    BIOC_RBWA_BWA_MEM_LONG_READS(ch_input)

    emit:
    tables   = BIOC_RBWA_BWA_MEM_LONG_READS.out.tables
    plots    = BIOC_RBWA_BWA_MEM_LONG_READS.out.plots
    objects  = BIOC_RBWA_BWA_MEM_LONG_READS.out.objects
    versions = BIOC_RBWA_BWA_MEM_LONG_READS.out.versions
}
