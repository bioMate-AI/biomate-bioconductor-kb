#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rblast — query_existing_blast_db
// Download, extract, and query an existing NCBI BLAST database using local BLAST.
// Input: 16S_ribosomal_RNA.tar.gz, RNA_example.fasta
// Container: quay.io/biocontainers/bioconductor-rblast:1.6.0--r45hdfd78af_0
// R packages: BiocFileCache, Biostrings, rBLAST
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBLAST_QUERY_EXISTING_BLAST_DB {
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
    .bm_deps <- c("BiocFileCache", "Biostrings", "rBLAST")
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
    library(BiocFileCache)
    
    # Check if BLAST+ is installed and in the PATH
    if (Sys.which("blastn") == "") {
      message("Warning: 'blastn' executable not found in PATH. Please ensure BLAST+ is installed.")
    }
    
    # To satisfy the requirement of reading the user-provided '16S_ribosomal_RNA.tar.gz'
    # from the working directory while faithfully calling 'blast_db_get', we pre-populate
    # the BiocFileCache used by rBLAST with our local file.
    message("Populating BLAST database cache with local '16S_ribosomal_RNA.tar.gz'...")
    bfc <- blast_db_cache()
    db_url <- "https://ftp.ncbi.nlm.nih.gov/blast/db/16S_ribosomal_RNA.tar.gz"
    
    # Add the local file to the cache if it is not already present
    if (nrow(bfcquery(bfc, db_url, field = "rname")) == 0) {
      bfcadd(bfc, rname = db_url, fpath = "16S_ribosomal_RNA.tar.gz", action = "copy")
    }
    
    # --- Download/retrieve the database archive using blast_db_get ---
    message("Retrieving database archive path...")
    tgz_file <- blast_db_get ( "16S_ribosomal_RNA.tar.gz" )
    
    # --- Extract the database files using untar ---
    message("Extracting database files...")
    untar (tgz_file, exdir = "16S_rRNA_DB" )
    
    # --- Load the BLAST database using blast ---
    message("Loading BLAST database...")
    bl <- blast ( db = "./16S_rRNA_DB/16S_ribosomal_RNA" )
    
    # --- Read query sequences using readRNAStringSet (adapted from ---
    message("Reading query sequences...")
    seq <- readRNAStringSet ( "RNA_example.fasta" )[ 1 ]
    
    # --- Query the database using predict with default arguments ---
    message("Running BLAST query (default)...")
    cl <- predict (bl, seq)
    
    # Save default query results
    write.csv(cl, "blast_results_default.csv", row.names = FALSE)
    saveRDS(cl, "blast_results_default.rds")
    
    # --- Query the database using predict with custom arguments ---
    message("Running BLAST query (custom format and identity threshold)...")
    fmt <- paste ( "qaccver saccver pident length mismatch gapopen qstart qend" , "sstart send evalue bitscore qseq sseq" )
    cl <- predict (bl, seq, BLAST_args = "-perc_identity 99" , custom_format = fmt )
    
    # Save custom query results
    write.csv(cl, "blast_results_custom.csv", row.names = FALSE)
    saveRDS(cl, "blast_results_custom.rds")
    
    message("Pipeline completed successfully. Outputs saved to 'blast_results_default.csv' and 'blast_results_custom.csv'.")

    writeLines(c(
        '"BIOC_RBLAST_QUERY_EXISTING_BLAST_DB":',
        paste0('        rblast: ', as.character(packageVersion("rblast")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_query_existing_blast_db.csv versions.yml
    """
}

workflow BIOC_RBLAST_QUERY_EXISTING_BLAST_DB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 16S_ribosomal_RNA.tar.gz, RNA_example.fasta ] ]

    main:
    BIOC_RBLAST_QUERY_EXISTING_BLAST_DB(ch_input)

    emit:
    tables   = BIOC_RBLAST_QUERY_EXISTING_BLAST_DB.out.tables
    plots    = BIOC_RBLAST_QUERY_EXISTING_BLAST_DB.out.plots
    objects  = BIOC_RBLAST_QUERY_EXISTING_BLAST_DB.out.objects
    versions = BIOC_RBLAST_QUERY_EXISTING_BLAST_DB.out.versions
}
