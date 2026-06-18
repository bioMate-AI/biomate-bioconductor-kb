#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximeta — mixed_reference_oarfish_import
// Import and update metadata for mixed reference transcripts (annotated + novel) quantified with oarfish.
// Input: sgnex_h9_rep2.quant.gz, sgnex_h9_rep2.meta_info.json, coldata, novel_gr
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
    
    # Load required libraries quietly
    suppressPackageStartupMessages({
      library(tximeta)
      library(GenomicRanges)
      library(SummarizedExperiment)
    })

    # Point tximeta's BiocFileCache at a writable, non-interactive temp location so
    # makeLinkedTxpData() / loadLinkedTxome() never prompt for a cache directory.
    temp_bfc <- file.path(tempdir(), "tximeta_bfc")
    dir.create(temp_bfc, showWarnings = FALSE, recursive = TRUE)
    setTximetaBFC(temp_bfc, quiet = TRUE)

    # ==========================================
    # --- Read User Input Files ---
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
    # --- Run tximeta Pipeline ---
    # ==========================================
    
    # Import un-ranged data using importData with type="oarfish"
    se <- importData(coldata, type="oarfish")
    
    # Inspect reference digests using inspectDigests
    digests <- inspectDigests(se)
    digests_full <- inspectDigests(se, fullDigest=TRUE)

    # Link the user-provided NOVEL transcript metadata to the novel reference
    # digest that oarfish recorded for this index. This is the documented
    # mixed-reference step: makeLinkedTxpData registers the novel GRanges against
    # its sequence digest so that updateMetadata can resolve the 'novel' index.
    # Without this, updateMetadata cannot attach any metadata for an unregistered
    # custom/novel reference (tximeta only ranges indices it can resolve).
    digestList <- metadata(se)\$quantInfo\$digest[, 1]
    novel_seq_digest <- digestList\$novel_transcripts_digest\$sha256_digests\$sha256_seqs
    makeLinkedTxpData(
        digest    = novel_seq_digest,
        indexName = "novel",
        txpData   = novel_gr,
        source    = "LocalNovel",
        organism  = "Homo sapiens",
        release   = "NA",
        genome    = "NA"
    )

    # Resolve which reference indices actually carry registered metadata, so we
    # only ask updateMetadata for those (it errors on an index with no metadata).
    # The 'novel' index is now linked above; 'annotated' would be added the same
    # way if the user registered a linkedTxome for the annotated reference.
    resolvable <- intersect(c("annotated", "novel"),
                            digests\$index[!is.na(digests\$linkedTxpData) |
                                           !is.na(digests\$linkedTxome) |
                                           digests\$index == "novel"])
    if (length(resolvable) == 0) resolvable <- "novel"

    # Update metadata: attach the registered (novel) transcript annotation.
    se_update <- updateMetadata(se, order = resolvable)

    # Manually add novel transcript ranges using updateMetadata with txpData and
    # ranges=TRUE -> builds a RangedSummarizedExperiment for the matched novel txps.
    se_with_ranges <- updateMetadata(se, txpData = novel_gr, ranges = TRUE,
                                     order = c(resolvable, "user"))
    
    # ==========================================
    # --- Save Outputs ---
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
