#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pgca — protein_group_resolution
// Build a global protein group dictionary from multiple proteomics experimental runs and apply it to translate local protein groups into comparable global protein
// Input: run1.txt, run2.txt
// Container: quay.io/biocontainers/bioconductor-pgca:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: pgca
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the global protein group dictionary using pgcaDict from data frames, files, or a directory
//  * 2. [Core Analysis] Apply the dictionary to the experimental datasets using applyDict to append global Protein Group Codes (PGC)
//  * 3. [Visualization & Output] Save the generated dictionary to a text file using saveDict

nextflow.enable.dsl = 2

process BIOC_PGCA_PROTEIN_GROUP_RESOLUTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("pgca")
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
    library(pgca)
    
    # Check if input files exist in the working directory
    if (!file.exists("run1.txt") || !file.exists("run2.txt")) {
      stop("Error: 'run1.txt' and/or 'run2.txt' not found in the working directory.")
    }
    
    # Read the user input files
    run1_raw <- read.delim("run1.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    run2_raw <- read.delim("run2.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    # Helper function to standardize column names to match PGCA expectations
    # (N: local group ID, Accession: accession, Gene_Symbol: gene symbol, Protein_Name: protein name)
    standardize_cols <- function(df) {
      colnames(df) <- gsub("local.*group.*id|group.*id|^n\$", "N", colnames(df), ignore.case = TRUE)
      colnames(df) <- gsub("^accession\$", "Accession", colnames(df), ignore.case = TRUE)
      colnames(df) <- gsub("gene.*symbol|^gene\$", "Gene_Symbol", colnames(df), ignore.case = TRUE)
      colnames(df) <- gsub("protein.*name|^protein\$", "Protein_Name", colnames(df), ignore.case = TRUE)
      return(df)
    }
    
    run1 <- standardize_cols(run1_raw)
    run2 <- standardize_cols(run2_raw)
    
    # Create a temporary directory to store standardized files for file/directory-based dictionary building
    temp_dir <- tempfile("pgca_runs")
    dir.create(temp_dir, showWarnings = FALSE, recursive = TRUE)
    
    file1_path <- file.path(temp_dir, "run1.txt")
    file2_path <- file.path(temp_dir, "run2.txt")
    
    write.table(run1, file1_path, sep = "\t", row.names = FALSE, quote = FALSE)
    write.table(run2, file2_path, sep = "\t", row.names = FALSE, quote = FALSE)
    
    # Stage 1: Build the global protein group dictionary from data frames
    dict <- pgcaDict(
      run1,
      run2,
      col.mapping = c(gene.symbol = "Gene_Symbol")
    )
    
    # Stage 2: Apply the dictionary to the experimental datasets (data frames)
    translated <- applyDict(run1, run2, dict = dict)
    
    # Stage 3: Build the dictionary from individual files
    dict.from.files <- pgcaDict(
      file1_path,
      file2_path,
      col.mapping = c(gene.symbol = "Gene_Symbol")
    )
    
    # Stage 4: Build the dictionary from a directory containing the files
    dict.from.dir <- pgcaDict(
      temp_dir,
      col.mapping = c(gene.symbol = "Gene_Symbol")
    )
    
    # Stage 5: Apply the directory-built dictionary to the datasets
    translated2 <- applyDict(run1, run2, dict = dict.from.dir)
    
    # Stage 6: Save the generated dictionary to a text file
    dictOutFile <- "global_protein_group_dictionary.txt"
    saveDict(dict.from.dir, file = dictOutFile)
    
    # Save meaningful results to output files
    # Save the dictionary object as an RDS file
    saveRDS(dict.from.dir, "global_protein_group_dictionary.rds")
    
    # Save translated datasets as CSV files
    if (!is.null(translated2\$run1)) {
      write.csv(translated2\$run1, "translated_run1.csv", row.names = FALSE)
    } else if (length(translated2) >= 1) {
      write.csv(translated2[[1]], "translated_run1.csv", row.names = FALSE)
    }
    
    if (!is.null(translated2\$run2)) {
      write.csv(translated2\$run2, "translated_run2.csv", row.names = FALSE)
    } else if (length(translated2) >= 2) {
      write.csv(translated2[[2]], "translated_run2.csv", row.names = FALSE)
    }
    
    # Clean up temporary directory
    unlink(temp_dir, recursive = TRUE)
    
    cat("PGCA pipeline completed successfully.\n")
    cat("Outputs saved:\n")
    cat(" - global_protein_group_dictionary.txt (Text dictionary)\n")
    cat(" - global_protein_group_dictionary.rds (R object dictionary)\n")
    cat(" - translated_run1.csv (Translated Run 1 with PGC codes)\n")
    cat(" - translated_run2.csv (Translated Run 2 with PGC codes)\n")

    writeLines(c(
        '"BIOC_PGCA_PROTEIN_GROUP_RESOLUTION":',
        paste0('    pgca: ', as.character(packageVersion('pgca')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_group_resolution.csv versions.yml
    """
}

workflow BIOC_PGCA_PROTEIN_GROUP_RESOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ run1.txt, run2.txt ] ]

    main:
    BIOC_PGCA_PROTEIN_GROUP_RESOLUTION(ch_input)

    emit:
    tables   = BIOC_PGCA_PROTEIN_GROUP_RESOLUTION.out.tables
    plots    = BIOC_PGCA_PROTEIN_GROUP_RESOLUTION.out.plots
    objects  = BIOC_PGCA_PROTEIN_GROUP_RESOLUTION.out.objects
    versions = BIOC_PGCA_PROTEIN_GROUP_RESOLUTION.out.versions
}
