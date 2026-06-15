#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rbwa — bwa_backtrack_alignment
// Align short DNA sequencing reads (up to 100bp) to a reference genome using BWA-backtrack, generating intermediate SAI files and converting them to SAM format.
// Input: fasta, fastq
// Container: quay.io/biocontainers/bioconductor-rbwa:1.14.0--r45h01b2380_0
// R packages: Rbwa
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT {
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
    
    # Load required library
    library(Rbwa)
    
    # --- Locate input files in the working directory ---
    fasta_files <- list.files(pattern = "\\\\.(fa|fasta)\$")
    fastq_files_list <- list.files(pattern = "\\\\.(fq|fastq)\$")
    
    if (length(fasta_files) == 0) {
      stop("Error: No reference genome FASTA file (.fa or .fasta) found in the working directory.")
    }
    if (length(fastq_files_list) == 0) {
      stop("Error: No short-read sequencing FASTQ file (.fq or .fastq) found in the working directory.")
    }
    
    # Use the first matching files found
    fasta <- fasta_files[1]
    fastq <- fastq_files_list[1]
    
    # Create a directory for the index files to keep the workspace clean
    index_dir <- "bwa_index"
    if (!dir.exists(index_dir)) {
      dir.create(index_dir)
    }
    index_prefix <- file.path(index_dir, "ref_index")
    
    # --- Build reference genome index ---
    message("Building BWA index...")
    bwa_build_index(fasta,
                    index_prefix=index_prefix)
    
    # --- Align reads to the index to generate intermediate SAI file ---
    sai_file <- "output.sai"
    message("Aligning reads (bwa_aln)...")
    bwa_aln(index_prefix=index_prefix,
            fastq_files=fastq,
            sai_files=sai_file)
    
    # --- Convert SAI file to SAM format ---
    sam_file <- "output.sam"
    message("Converting SAI to SAM (bwa_sam)...")
    bwa_sam(index_prefix=index_prefix,
            fastq_files=fastq,
            sai_files=sai_file,
            sam_file=sam_file)
    
    # --- Expand secondary alignments from XA tags ---
    multi_sam_file <- "output.multi.sam"
    message("Expanding secondary alignments (xa2multi)...")
    xa2multi(sam_file,
             multi_sam_file)
    
    # --- Generate a summary report of the alignments ---
    message("Generating alignment summary report...")
    if (file.exists(sam_file)) {
      sam_lines <- readLines(sam_file)
      alignment_lines <- sam_lines[!grepl("^@", sam_lines)]
      
      if (length(alignment_lines) > 0) {
        sam_fields <- strsplit(alignment_lines, "\t")
        
        # Extract basic SAM fields safely
        qname <- sapply(sam_fields, function(x) if(length(x) >= 1) x[1] else NA)
        flag <- sapply(sam_fields, function(x) if(length(x) >= 2) as.numeric(x[2]) else NA)
        rname <- sapply(sam_fields, function(x) if(length(x) >= 3) x[3] else NA)
        pos <- sapply(sam_fields, function(x) if(length(x) >= 4) as.numeric(x[4]) else NA)
        mapq <- sapply(sam_fields, function(x) if(length(x) >= 5) as.numeric(x[5]) else NA)
        
        summary_df <- data.frame(
          QueryName = qname,
          Flag = flag,
          Reference = rname,
          Position = pos,
          MapQ = mapq,
          stringsAsFactors = FALSE
        )
        
        write.csv(summary_df, "alignment_summary.csv", row.names = FALSE)
        message("Alignment summary successfully written to 'alignment_summary.csv'.")
      } else {
        warning("No alignments found in the SAM file.")
      }
    }

    writeLines(c(
        '"BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT":',
        paste0('        rbwa: ', as.character(packageVersion("rbwa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bwa_backtrack_alignment.csv versions.yml
    """
}

workflow BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fasta, fastq ] ]

    main:
    BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT.out.tables
    plots    = BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT.out.plots
    objects  = BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT.out.objects
    versions = BIOC_RBWA_BWA_BACKTRACK_ALIGNMENT.out.versions
}
