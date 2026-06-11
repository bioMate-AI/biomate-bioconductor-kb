#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rbwa — bwa_mem_alignment
// Align longer DNA sequencing reads (70bp to 1Mbp) directly to a reference genome using BWA-MEM, generating a SAM file directly.
// Input: fasta, fastq
// Container: quay.io/biocontainers/bioconductor-rbwa:1.14.0--r45h01b2380_0
// R packages: Rbwa
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBWA_BWA_MEM_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rbwa:1.14.0--r45h01b2380_0"

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
    
    # Load the required library
    library(Rbwa)
    
    # Define input file paths from the working directory as specified
    fasta <- "fasta"
    fastq <- "fastq"
    
    # Verify input files exist in the working directory
    if (!file.exists(fasta)) {
      stop("Error: Reference genome FASTA file 'fasta' not found in the working directory.")
    }
    if (!file.exists(fastq)) {
      stop("Error: Sequencing FASTQ file 'fastq' not found in the working directory.")
    }
    
    # Create a temporary directory for storing the index files
    dir <- tempdir()
    index_prefix <- file.path(dir, "ref_index")
    
    # --- Build reference genome index using bwa_build_index ---
    message("Building reference genome index...")
    bwa_build_index(fasta,
                    index_prefix=index_prefix)
    
    # --- Align reads directly to the index using bwa_mem to ---
    message("Aligning reads using BWA-MEM...")
    output_sam <- "output.sam"
    bwa_mem(index_prefix=index_prefix,
            fastq_files=fastq,
            sam_file=output_sam)
    
    # Verify output and write a preview log
    if (file.exists(output_sam)) {
      message("Alignment completed successfully. Output saved to: ", output_sam)
      
      # Read and write a preview of the SAM file
      sam_lines <- readLines(output_sam, n = 20)
      writeLines(sam_lines, "output_sam_preview.txt")
      message("A preview of the SAM file has been saved to 'output_sam_preview.txt'")
    } else {
      stop("Error: SAM file was not generated.")
    }

    writeLines(c(
        '"BIOC_RBWA_BWA_MEM_ALIGNMENT":',
        paste0('        rbwa: ', as.character(packageVersion("rbwa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bwa_mem_alignment.csv versions.yml
    """
}

workflow BIOC_RBWA_BWA_MEM_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fasta, fastq ] ]

    main:
    BIOC_RBWA_BWA_MEM_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_RBWA_BWA_MEM_ALIGNMENT.out.tables
    plots    = BIOC_RBWA_BWA_MEM_ALIGNMENT.out.plots
    objects  = BIOC_RBWA_BWA_MEM_ALIGNMENT.out.objects
    versions = BIOC_RBWA_BWA_MEM_ALIGNMENT.out.versions
}
