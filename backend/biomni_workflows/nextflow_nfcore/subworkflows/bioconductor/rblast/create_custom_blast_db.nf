#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rblast — create_custom_blast_db
// Create a custom BLAST database from user-provided sequences and query it locally.
// Input: RNA_example.fasta, fragment
// Container: quay.io/biocontainers/bioconductor-rblast:1.6.0--r45hdfd78af_0
// R packages: Biostrings, rBLAST
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rblast:1.6.0--r45hdfd78af_0"

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
    
    # Load required libraries
    library(rBLAST)
    library(Biostrings)
    
    # --- Read sequences using readRNAStringSet from the ---
    seq <- readRNAStringSet("RNA_example.fasta")
    
    # --- Write sequences to a FASTA file using writeXStringSet ---
    writeXStringSet(seq, filepath = "seqs.fasta")
    
    # --- Build the BLAST database using makeblastdb ---
    makeblastdb("seqs.fasta", db_name = "db/small", dbtype = "nucl")
    
    # --- Load the custom database using blast ---
    db <- blast("db/small")
    
    # --- Extract a query fragment using subseq (documented stage) ---
    fragment <- subseq(seq[1], start = 101, end = 200)
    
    # Read the user-provided query sequence from the "fragment" file
    # and use it as the query sequence for the prediction
    if (file.exists("fragment")) {
      fragment <- readRNAStringSet("fragment")
    }
    
    # --- Query the custom database using predict ---
    results <- predict(db, fragment)
    
    # Write named output files for the meaningful results
    write.csv(results, "blast_results.csv", row.names = FALSE)
    saveRDS(results, "blast_results.rds")

    writeLines(c(
        '"BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB":',
        paste0('        rblast: ', as.character(packageVersion("rblast")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_custom_blast_db.csv versions.yml
    """
}

workflow BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RNA_example.fasta, fragment ] ]

    main:
    BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB(ch_input)

    emit:
    tables   = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.tables
    plots    = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.plots
    objects  = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.objects
    versions = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.versions
}
