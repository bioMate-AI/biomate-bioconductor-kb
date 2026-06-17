#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rbowtie — ungapped_alignment_bowtie
// Build a reference genome index and align short reads to generate ungapped alignments in SAM format.
// Input: refFiles, readsFiles
// Container: quay.io/biocontainers/bioconductor-rbowtie:1.50.0--r45ha27e39d_0
// R packages: biocmanager, Rbowtie
// Bioconductor: 3.20 | R: 4.4
// Requires: Rbowtie
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build reference index using bowtie_build
//  * 2. [Core Analysis] Align short reads to the index using bowtie

nextflow.enable.dsl = 2

process BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE {
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
    .bm_deps <- c("biocmanager", "Rbowtie")
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
        
        # Load required library
        library(Rbowtie)
        
        # 1. Identify User Input Files from the Working Directory
        # Reference genome files (FASTA format)
        refFiles <- list.files(pattern = "\\\\.(fa|fasta|fna)\$", full.names = TRUE)
        if (length(refFiles) == 0) {
          stop("Error: No reference genome FASTA files (*.fa, *.fasta, *.fna) found in the working directory.")
        }
        
        # Short read files (FASTQ/FASTA format)
        # Look for .fq or .fastq first. If none, look for .fa/.fasta that are not in refFiles.
        is_fasta <- FALSE
        readsFiles <- list.files(pattern = "\\\\.(fq|fastq)\$", full.names = TRUE)
        if (length(readsFiles) == 0) {
          potentialReads <- list.files(pattern = "\\\\.(fa|fasta)\$", full.names = TRUE)
          readsFiles <- setdiff(potentialReads, refFiles)
          is_fasta <- TRUE
        }
        
        if (length(readsFiles) == 0) {
          stop("Error: No short read files (*.fq, *.fastq, or non-reference *.fa, *.fasta) found in the working directory.")
        }
        
        # 2. Build Reference Index using bowtie_build
        indexDir <- file.path(tempdir(), "refsIndex")
        if (!dir.exists(indexDir)) {
          dir.create(indexDir, recursive = TRUE)
        }
        
        tmp <- bowtie_build(references=refFiles, outdir=indexDir, prefix="index", force=TRUE)
        
        # Save the build log/output
        write.csv(data.frame(log_message = tmp), file = "bowtie_build_log.csv", row.names = FALSE)
        
        # 3. Align Short Reads to the Index using bowtie
        samFiles <- "alignments.sam"
        
        if (is_fasta) {
          bowtie(sequences=readsFiles, 
                 index=file.path(indexDir, "index"), 
                 outfile=samFiles, 
                 sam=TRUE, 
                 best=TRUE, 
                 force=TRUE,
                 f=TRUE)
        } else {
          bowtie(sequences=readsFiles, 
                 index=file.path(indexDir, "index"), 
                 outfile=samFiles, 
                 sam=TRUE, 
                 best=TRUE, 
                 force=TRUE)
        }
        
        # 4. Generate and Save Alignment Summary
        if (file.exists(samFiles)) {
          con <- file(samFiles, "r")
          total_lines <- 0
          header_lines <- 0
          
          while (TRUE) {
            chunk <- readLines(con, n = 100000, warn = FALSE)
            if (length(chunk) == 0) {
              break
            }
            total_lines <- total_lines + length(chunk)
            header_lines <- header_lines + sum(grepl("^@", chunk))
          }
          close(con)
          
          alignment_records <- total_lines - header_lines
          
          summary_df <- data.frame(
            Metric = c("Total_SAM_Lines", "Header_Lines", "Alignment_Records"),
            Value = c(total_lines, header_lines, alignment_records)
          )
          write.csv(summary_df, file = "alignment_summary.csv", row.names = FALSE)
        } else {
          warning("SAM output file was not created.")
        }

    writeLines(c(
        '"BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE":',
        paste0('    Rbowtie: ', as.character(packageVersion('Rbowtie')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ungapped_alignment_bowtie.csv versions.yml
    """
}

workflow BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ refFiles, readsFiles ] ]

    main:
    BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE(ch_input)

    emit:
    tables   = BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE.out.tables
    plots    = BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE.out.plots
    objects  = BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE.out.objects
    versions = BIOC_RBOWTIE_UNGAPPED_ALIGNMENT_BOWTIE.out.versions
}
