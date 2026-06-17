#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: signatureSearch — batch_gess_processing
// Process multiple query signatures in parallel using multi-core CPUs or cluster environments.
// Input: batch_queries, refdb
// Container: quay.io/biocontainers/bioconductor-signaturesearch:1.24.0--r45ha27e39d_0
// R packages: BiocParallel, readr, signatureSearch
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, readr, signatureSearch
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define a list of query signatures
//  * 2. [Visualization & Output] Define a processing function that initializes qSig, runs gess_lincs, and writes results
//  * 3. [Core Analysis] Execute parallel processing using bplapply (for multi-core) or batchMap/submitJobs (for cluster environments)

nextflow.enable.dsl = 2

process BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING {
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
    .bm_deps <- c("BiocParallel", "readr", "signatureSearch")
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
        
        library(signatureSearch)
        library(BiocParallel)
        library(readr)
        
        # 1. Read user input files from the working directory
        if (file.exists("batch_queries.rds")) {
            batch_queries <- readRDS("batch_queries.rds")
        } else if (file.exists("batch_queries")) {
            batch_queries <- readRDS("batch_queries")
        } else {
            stop("Required input file 'batch_queries' or 'batch_queries.rds' not found in the working directory.")
        }
        
        if (file.exists("refdb.txt")) {
            refdb <- readLines("refdb.txt", warn = FALSE)[1]
        } else if (file.exists("refdb")) {
            refdb <- "refdb"
        } else {
            stop("Required reference database file or path 'refdb' or 'refdb.txt' not found in the working directory.")
        }
        
        if(!dir.exists("batch_res")){
            dir.create("batch_res")
        }
        
        # 2. Define the processing function that initializes qSig, runs gess_lincs, and writes results
        f_bp <- function(i){
            qsig_lincs <- qSig(query = batch_queries[[i]],
                           gess_method="LINCS", refdb=refdb)
            lincs <- gess_lincs(qsig_lincs, sortby="NCS", tau=TRUE)
            write_tsv(result(lincs), paste0("batch_res/lincs_res_", i, ".tsv"))
            return(result(lincs))
        }
        
        # 3. Execute parallel processing using bplapply
        gess_list <- bplapply(seq_along(batch_queries), f_bp, BPPARAM = MulticoreParam(workers = 2))
        
        # Save the final list of results as an RDS object
        saveRDS(gess_list, "gess_list.rds")

    writeLines(c(
        '"BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING":',
        paste0('    signatureSearch: ', as.character(packageVersion('signatureSearch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_gess_processing.csv versions.yml
    """
}

workflow BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ batch_queries, refdb ] ]

    main:
    BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING(ch_input)

    emit:
    tables   = BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING.out.tables
    plots    = BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING.out.plots
    objects  = BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING.out.objects
    versions = BIOC_SIGNATURESEARCH_BATCH_GESS_PROCESSING.out.versions
}
