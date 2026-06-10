#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylKit — large_data_tabix_db
// Read and manage large-scale bisulfite sequencing datasets using flat-file databases (Tabix) to minimize memory usage.
// Input: file.list, methylBase.obj, mydbpath
// Container: quay.io/biocontainers/bioconductor-methylkit:1.36.0--r45ha27e39d_0
// R packages: methylKit
// Bioconductor: 3.20 | R: 4.4
// Requires: methylKit
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read raw files directly into a Tabix-backed methylRawListDB object
//  * 2. [Core Analysis] Convert an in-memory object to a flat-file database
//  * 3. [Input & Preparation] Load an existing flat-file database using its file path

nextflow.enable.dsl = 2

process BIOC_METHYLKIT_LARGE_DATA_TABIX_DB {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("methylKit")
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
    library(methylKit)
    
    # 1. Read User Inputs from the working directory
    if (file.exists("file.list")) {
      file.list <- tryCatch({
        readRDS("file.list")
      }, error = function(e) {
        as.list(readLines("file.list"))
      })
    } else {
      stop("Error: 'file.list' not found in the working directory.")
    }
    
    if (file.exists("methylBase.obj")) {
      methylBase.obj <- readRDS("methylBase.obj")
    } else {
      stop("Error: 'methylBase.obj' not found in the working directory.")
    }
    
    if (file.exists("mydbpath")) {
      # Check if 'mydbpath' is a text file containing the path, or the tabix file itself
      # Use magic numbers to check for gzip/bgzip compression to avoid readLines warnings on binary files
      magic <- readBin("mydbpath", what = "raw", n = 2)
      is_bgz <- length(magic) == 2 && magic[1] == as.raw(0x1f) && magic[2] == as.raw(0x8b)
      
      if (is_bgz) {
        mydbpath <- "mydbpath"
      } else {
        first_line <- tryCatch(readLines("mydbpath", n = 1, warn = FALSE), error = function(e) "")
        if (file.exists(first_line)) {
          mydbpath <- first_line
        } else {
          mydbpath <- "mydbpath"
        }
      }
    } else {
      stop("Error: 'mydbpath' not found in the working directory.")
    }
    
    # 2. Execute the documented workflow steps exactly as specified
    n_files <- length(file.list)
    sample_ids <- as.list(paste0("sample", seq_len(n_files)))
    treatments <- rep(c(1, 0), length.out = n_files)
    
    myobjDB=methRead(file.list,
               sample.id=sample_ids,
               assembly="hg18",
               treatment=treatments,
               context="CpG",
               dbtype = "tabix",
               dbdir = "methylDB"
               )
    
    objDB=makeMethylDB(methylBase.obj,"exMethylDB")
    
    loadedDB=readMethylDB(mydbpath)
    
    # 3. Save meaningful results to output files
    saveRDS(myobjDB, "myobjDB.rds")
    saveRDS(objDB, "objDB.rds")
    saveRDS(loadedDB, "loadedDB.rds")
    
    # Write summaries to text files
    writeLines(capture.output(show(myobjDB)), "myobjDB_summary.txt")
    writeLines(capture.output(show(objDB)), "objDB_summary.txt")
    writeLines(capture.output(show(loadedDB)), "loadedDB_summary.txt")

    writeLines(c(
        '"BIOC_METHYLKIT_LARGE_DATA_TABIX_DB":',
        paste0('    methylKit: ', as.character(packageVersion('methylKit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_large_data_tabix_db.csv versions.yml
    """
}

workflow BIOC_METHYLKIT_LARGE_DATA_TABIX_DB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.list, methylBase.obj, mydbpath ] ]

    main:
    BIOC_METHYLKIT_LARGE_DATA_TABIX_DB(ch_input)

    emit:
    tables   = BIOC_METHYLKIT_LARGE_DATA_TABIX_DB.out.tables
    plots    = BIOC_METHYLKIT_LARGE_DATA_TABIX_DB.out.plots
    objects  = BIOC_METHYLKIT_LARGE_DATA_TABIX_DB.out.objects
    versions = BIOC_METHYLKIT_LARGE_DATA_TABIX_DB.out.versions
}
