#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rBLAST — create_and_query_custom_db
// Create a custom BLAST database from a set of sequences and query it with a sequence fragment.
// Input: RNA_example.fasta, fragment
// Container: quay.io/biocontainers/bioconductor-rblast:1.6.0--r45hdfd78af_0
// R packages: Biostrings, rBLAST
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, rBLAST
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read reference sequences using readRNAStringSet
//  * 2. [Visualization & Output] Write sequences to a FASTA file using writeXStringSet
//  * 3. [Input & Preparation] Create a custom BLAST database using makeblastdb
//  * 4. [Input & Preparation] Load the custom database using blast
//  * 5. [Core Analysis] Extract a query fragment using subseq
//  * 6. [Core Analysis] Query the custom database using predict

nextflow.enable.dsl = 2

process BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB {
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
    .bm_deps <- c("Biostrings", "rBLAST")
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
    library(rBLAST)
    library(Biostrings)
    
    # 1. Read reference sequences and the fragment file from the working directory
    seq <- readRNAStringSet("RNA_example.fasta")
    fragment <- readRNAStringSet("fragment")
    
    # 2. Write sequences to a FASTA file using writeXStringSet
    writeXStringSet(seq, filepath = "seqs.fasta")
    
    # 3. Create a custom BLAST database using makeblastdb
    # Wrap in tryCatch to handle environments where BLAST+ is not installed
    tryCatch({
      # Ensure the database directory exists before creating the BLAST database
      dir.create("db", showWarnings = FALSE, recursive = TRUE)
      makeblastdb("seqs.fasta", db_name = "db/small", dbtype = "nucl")
      
      # 4. Load the custom database using blast
      db <- blast("db/small")
      
      # 5. Use the provided fragment and extract a subsequence
      fragment <- subseq(fragment, start = 101, end = 200)
      
      # 6. Query the custom database using predict
      results <- predict(db, fragment)
      
      # Write the results to a CSV file
      write.csv(results, "blast_results.csv", row.names = FALSE)
      
    }, error = function(e) {
      message("BLAST execution failed. Ensure BLAST+ is installed and in your PATH.")
      message("Error details: ", e\$message)
      # Write an error CSV to ensure the output file is always created
      write.csv(data.frame(Error = e\$message), "blast_results.csv", row.names = FALSE)
    })

    writeLines(c(
        '"BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB":',
        paste0('    rBLAST: ', as.character(packageVersion('rBLAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_and_query_custom_db.csv versions.yml
    """
}

workflow BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RNA_example.fasta, fragment ] ]

    main:
    BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB(ch_input)

    emit:
    tables   = BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB.out.tables
    plots    = BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB.out.plots
    objects  = BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB.out.objects
    versions = BIOC_RBLAST_CREATE_AND_QUERY_CUSTOM_DB.out.versions
}
