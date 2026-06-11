#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximeta — mixed_reference_oarfish_import
// Import and update metadata for mixed reference transcripts (annotated + novel) quantified with oarfish.
// Input: sgnex_h9_rep2.quant.gz, coldata, novel_gr
// Container: quay.io/biocontainers/bioconductor-tximeta:1.28.2--r45hdfd78af_0
// R packages: GenomicRanges, SummarizedExperiment, tximeta
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tximeta:1.28.2--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "SummarizedExperiment", "tximeta")
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
    
    # Load required libraries quietly
    suppressPackageStartupMessages({
      library(tximeta)
      library(GenomicRanges)
      library(SummarizedExperiment)
    })
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Locate and read coldata (sample metadata table)
    coldata_file <- NULL
    for (f in c("coldata", "coldata.csv", "coldata.tsv", "coldata.rds")) {
      if (file.exists(f)) {
        coldata_file <- f
        break
      }
    }
    if (is.null(coldata_file)) {
      stop("Error: Could not find coldata file (coldata, coldata.csv, coldata.tsv, or coldata.rds) in the working directory.")
    }
    
    if (grepl("\\\\.rds\$", coldata_file, ignore.case = TRUE)) {
      coldata <- readRDS(coldata_file)
    } else if (grepl("\\\\.tsv\$", coldata_file, ignore.case = TRUE)) {
      coldata <- read.delim(coldata_file, stringsAsFactors = FALSE)
    } else {
      coldata <- read.csv(coldata_file, stringsAsFactors = FALSE)
    }
    
    # Validate coldata structure
    if (!"files" %in% colnames(coldata)) {
      stop("Error: coldata must contain a 'files' column pointing to the quantification files.")
    }
    if (!"names" %in% colnames(coldata)) {
      stop("Error: coldata must contain a 'names' column with unique sample names.")
    }
    
    # Ensure file paths in coldata point to existing files in the working directory
    coldata\$files <- sapply(coldata\$files, function(f) {
      if (file.exists(f)) {
        return(f)
      }
      base_f <- basename(f)
      if (file.exists(base_f)) {
        return(base_f)
      }
      # Fallback: search for any matching .quant.gz file in the working directory
      gz_files <- list.files(pattern = "\\\\.quant\\\\.gz\$")
      if (length(gz_files) > 0) {
        match_idx <- grep(gsub("\\\\.quant\\\\.gz\$", "", base_f), gz_files)
        if (length(match_idx) > 0) {
          return(gz_files[match_idx[1]])
        }
      }
      return(f)
    })
    
    # Locate and read novel_gr (GRanges object containing novel transcript coordinates)
    novel_gr_file <- NULL
    for (f in c("novel_gr.rds", "novel_gr")) {
      if (file.exists(f)) {
        novel_gr_file <- f
        break
      }
    }
    if (is.null(novel_gr_file)) {
      stop("Error: Could not find novel_gr file (novel_gr.rds or novel_gr) in the working directory.")
    }
    novel_gr <- readRDS(novel_gr_file)
    
    # Ensure names are set on the GRanges object as required by tximeta
    if (is.null(names(novel_gr))) {
      if ("tx_name" %in% colnames(mcols(novel_gr))) {
        names(novel_gr) <- mcols(novel_gr)\$tx_name
      } else if ("tx_id" %in% colnames(mcols(novel_gr))) {
        names(novel_gr) <- mcols(novel_gr)\$tx_id
      }
    }
    
    # ==========================================
    # 2. Run tximeta Pipeline
    # ==========================================
    
    # Import un-ranged data using importData with type="oarfish"
    se <- importData(coldata, type="oarfish")
    
    # Inspect reference digests using inspectDigests
    digests <- inspectDigests(se)
    digests_full <- inspectDigests(se, fullDigest=TRUE)
    
    # Update metadata (transcripts preserved, NA filled for missing metadata)
    se_update <- updateMetadata(se)
    
    # Manually add novel transcript ranges using updateMetadata with txpData and ranges=TRUE
    se_with_ranges <- updateMetadata(se, txpData=novel_gr, ranges=TRUE)
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save digest inspection tables
    write.csv(as.data.frame(digests), "digests.csv", row.names = FALSE)
    write.csv(as.data.frame(digests_full), "digests_full.csv", row.names = FALSE)
    
    # Save SummarizedExperiment objects
    saveRDS(se_update, "se_update.rds")
    saveRDS(se_with_ranges, "se_with_ranges.rds")
    
    message("Pipeline completed successfully. Outputs saved to digests.csv, digests_full.csv, se_update.rds, and se_with_ranges.rds.")

    writeLines(c(
        '"BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT":',
        paste0('        tximeta: ', as.character(packageVersion("tximeta")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixed_reference_oarfish_import.csv versions.yml
    """
}

workflow BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sgnex_h9_rep2.quant.gz, coldata, novel_gr ] ]

    main:
    BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT(ch_input)

    emit:
    tables   = BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT.out.tables
    plots    = BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT.out.plots
    objects  = BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT.out.objects
    versions = BIOC_TXIMETA_MIXED_REFERENCE_OARFISH_IMPORT.out.versions
}
