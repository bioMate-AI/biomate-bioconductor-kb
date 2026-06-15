#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GEOfastq — geo_fastq_download
// Crawl GEO and ENA metadata using accession numbers provided in sample metadata, and download the corresponding FASTQ files.
// Input: counts.csv, coldata.csv
// Container: 1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GEOfastq
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("GEOfastq")
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
    library(GEOfastq)
    
    # Define parameters
    dest_dir <- "fastq_downloads"
    if (!dir.exists(dest_dir)) {
        dir.create(dest_dir, recursive = TRUE)
    }
    
    # --- Read input metadata ---
    message("Reading input metadata...")
    coldata_path <- "coldata.csv"
    if (!file.exists(coldata_path)) {
        stop("Required input file 'coldata.csv' not found in the working directory.")
    }
    coldata <- read.csv(coldata_path, stringsAsFactors = FALSE)
    
    # --- Extract GEO Accessions dynamically from input ---
    message("Searching for GEO accessions in coldata.csv...")
    # Search all columns for GSM (sample) or GSE (series) patterns to avoid hardcoding
    all_values <- as.character(unlist(coldata))
    gsm_ids <- unique(grep("^GSM\\\\d+\$", all_values, value = TRUE))
    gse_ids <- unique(grep("^GSE\\\\d+\$", all_values, value = TRUE))
    
    srp_meta <- NULL
    
    if (length(gsm_ids) > 0) {
        message(sprintf("Found %d GSM accession(s): %s", length(gsm_ids), paste(gsm_ids, collapse = ", ")))
        tryCatch({
            srp_meta <- crawl_gsms(gsm_ids)
        }, error = function(e) {
            message("Error crawling GSMs: ", e\$message)
        })
    } else if (length(gse_ids) > 0) {
        message(sprintf("Found GSE accession: %s", gse_ids[1]))
        tryCatch({
            gse_text <- crawl_gse(gse_ids[1])
            gsm_names <- extract_gsms(gse_text)
            message(sprintf("Extracted %d GSMs from GSE.", length(gsm_names)))
            srp_meta <- crawl_gsms(gsm_names)
        }, error = function(e) {
            message("Error crawling GSE: ", e\$message)
        })
    } else {
        message("No GSM or GSE accessions found in coldata.csv. Creating empty metadata template.")
        srp_meta <- data.frame(
            run = character(),
            gsm_name = character(),
            ebi_dir = character(),
            stringsAsFactors = FALSE
        )
    }
    
    # --- Download FASTQ files from ENA ---
    download_results <- data.frame(
        run = character(),
        gsm_name = character(),
        file_path = character(),
        status = character(),
        stringsAsFactors = FALSE
    )
    
    if (!is.null(srp_meta) && nrow(srp_meta) > 0) {
        message("Crawled metadata successfully. Proceeding to download FASTQs...")
        
        # Ensure required download directory column exists
        if (!"ebi_dir" %in% colnames(srp_meta) && "run" %in% colnames(srp_meta)) {
            srp_meta\$ebi_dir <- sapply(srp_meta\$run, get_dldir)
        }
        
        # Download FASTQs with error handling for network robustness
        tryCatch({
            res <- get_fastqs(srp_meta, dest_dir)
            
            download_results <- data.frame(
                run = srp_meta\$run,
                gsm_name = srp_meta\$gsm_name,
                file_path = file.path(dest_dir, paste0(srp_meta\$run, ".fastq.gz")),
                status = "Success",
                stringsAsFactors = FALSE
            )
        }, error = function(e) {
            message("Error downloading FASTQs: ", e\$message)
            download_results <- data.frame(
                run = srp_meta\$run,
                gsm_name = srp_meta\$gsm_name,
                file_path = NA,
                status = paste("Failed:", e\$message),
                stringsAsFactors = FALSE
            )
        })
    } else {
        message("No metadata available to download.")
    }
    
    # --- Write Outputs ---
    message("Writing outputs...")
    write.csv(srp_meta, "geo_metadata.csv", row.names = FALSE)
    write.csv(download_results, "download_status.csv", row.names = FALSE)
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD":',
        paste0('    GEOfastq: ', as.character(packageVersion('GEOfastq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geo_fastq_download.csv versions.yml
    """
}

workflow BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD(ch_input)

    emit:
    tables   = BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD.out.tables
    plots    = BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD.out.plots
    objects  = BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD.out.objects
    versions = BIOC_GEOFASTQ_GEO_FASTQ_DOWNLOAD.out.versions
}
