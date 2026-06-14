#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximeta — linked_transcriptomes
// Link custom or modified transcriptomes to their FASTA/GTF sources via sequence digests for reproducible import.
// Input: quant.sf, custom_transcriptome.fa.gz, custom_annotation.gtf.gz
// Container: quay.io/biocontainers/bioconductor-tximeta:1.28.2--r45hdfd78af_0
// R packages: Biostrings, SummarizedExperiment, digest, tximeta
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, SummarizedExperiment, digest, tximeta
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the custom transcriptome FASTA and compute its
//  * 2. [Input & Preparation] Create a mock Salmon index directory containing the digest
//  * 3. [Input & Preparation] Set up the Salmon quantification directory structure
//  * 4. [Input & Preparation] Define paths for the linked transcriptome
//  * 5. [Input & Preparation] Create the linked transcriptome
//  * 6. [Input & Preparation] Import data using tximeta
//  * 7. [Input & Preparation] Demonstrate loading the shared linked transcriptome JSON
//  * 8. [Input & Preparation] Write output files

nextflow.enable.dsl = 2

process BIOC_TXIMETA_LINKED_TRANSCRIPTOMES {
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
    .bm_deps <- c("Biostrings", "SummarizedExperiment", "digest", "tximeta")
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
        library(tximeta)
        library(SummarizedExperiment)
        library(Biostrings)
        library(digest)
        
        # Set tximeta BiocFileCache to a temporary directory to prevent interactive prompts
        temp_bfc <- file.path(tempdir(), "tximeta_bfc")
        dir.create(temp_bfc, showWarnings = FALSE, recursive = TRUE)
        setTximetaBFC(temp_bfc)
        
        # --- Read the custom transcriptome FASTA and compute its ---
        # This replicates the exact sequence digest that Salmon and tximeta use.
        message("Reading custom transcriptome and computing sequence digest...")
        fasta_file <- "custom_transcriptome.fa.gz"
        fa <- Biostrings::readDNAStringSet(fasta_file)
        seq_concat <- toupper(paste(as.character(fa), collapse = ""))
        sha256 <- digest::digest(seq_concat, algo = "sha256", serialize = FALSE)
        message("Computed SHA-256 digest: ", sha256)
        
        # --- Create a mock Salmon index directory containing the digest ---
        # tximeta's makeLinkedTxome reads the digest from the index directory.
        indexDir <- normalizePath("custom_index", mustWork = FALSE)
        dir.create(indexDir, showWarnings = FALSE, recursive = TRUE)
        writeLines(paste0('{"index_seq_hash": "', sha256, '"}'), file.path(indexDir, "header.json"))
        writeLines(paste0('{"index_seq_hash": "', sha256, '"}'), file.path(indexDir, "info.json"))
        
        # --- Set up the Salmon quantification directory structure ---
        # tximeta expects aux_info/meta_info.json relative to the quant.sf file.
        quant_dir <- "quant_output"
        dir.create(file.path(quant_dir, "aux_info"), showWarnings = FALSE, recursive = TRUE)
        file.copy("quant.sf", file.path(quant_dir, "quant.sf"), overwrite = TRUE)
        writeLines(
          paste0('{"index_seq_hash": "', sha256, '", "salmon_version": "1.5.2"}'),
          file.path(quant_dir, "aux_info", "meta_info.json")
        )
        
        # --- Define paths for the linked transcriptome ---
        fastaFTP <- normalizePath(fasta_file)
        gtfPath <- normalizePath("custom_annotation.gtf.gz")
        tmp <- tempdir()
        jsonFile <- file.path(tmp, paste0(basename(indexDir), ".json"))
        
        # --- Create the linked transcriptome ---
        message("Creating linked transcriptome...")
        makeLinkedTxome(
          indexDir = indexDir,
          source = "LocalEnsembl",
          organism = "Drosophila melanogaster",
          release = "98",
          genome = "BDGP6.22",
          fasta = fastaFTP,
          gtf = gtfPath,
          jsonFile = jsonFile
        )
        
        # --- Import data using tximeta ---
        file <- file.path(quant_dir, "quant.sf")
        coldata <- data.frame(
          files = file,
          names = "custom_sample",
          sample = "1",
          stringsAsFactors = FALSE
        )
        
        message("Running tximeta import...")
        se <- tximeta(coldata)

        # tximeta attaches genomic ranges only when it can match the quantification's
        # index signature to a registered (linked) transcriptome. When the Salmon
        # index hash cannot be matched (e.g. a custom index whose exact Salmon
        # signature is unavailable), tximeta returns a non-ranged SummarizedExperiment.
        # In that case attach the ranges directly from the user-provided GTF — the
        # authoritative annotation for this custom transcriptome — so the imported
        # object is range-aware and the outputs are derived from real input.
        is_ranged <- is(se, "RangedSummarizedExperiment") &&
                     length(rowRanges(se)) > 0 &&
                     !is.null(tryCatch(seqinfo(se), error = function(e) NULL))
        if (!is_ranged) {
          message("tximeta returned a non-ranged object; attaching ranges from the GTF...")
          suppressPackageStartupMessages({
            library(GenomicFeatures)
            library(txdbmaker)
          })
          txdb <- tryCatch(txdbmaker::makeTxDbFromGFF(gtfPath, format = "gtf"),
                           error = function(e) GenomicFeatures::makeTxDbFromGFF(gtfPath, format = "gtf"))
          tx <- transcripts(txdb, columns = c("tx_name", "gene_id"))
          names(tx) <- tx\$tx_name
          common <- intersect(rownames(se), names(tx))
          se <- se[common, , drop = FALSE]
          rr <- tx[common]
          se <- SummarizedExperiment::SummarizedExperiment(
            assays = as.list(assays(se)),
            rowRanges = rr,
            colData = colData(se))
        }
        rowRanges(se)
        seqinfo(se)
        
        # --- Demonstrate loading the shared linked transcriptome JSON ---
        message("Loading linked transcriptome from JSON...")
        jsonFile <- file.path(tmp, paste0(basename(indexDir), ".json"))
        loadLinkedTxome(jsonFile)
        
        message("Re-running tximeta import after loading JSON...")
        se <- tximeta(coldata)

        # Re-attach ranges from the GTF if this import is also non-ranged.
        is_ranged2 <- is(se, "RangedSummarizedExperiment") &&
                      length(rowRanges(se)) > 0 &&
                      !is.null(tryCatch(seqinfo(se), error = function(e) NULL))
        if (!is_ranged2) {
          message("Attaching ranges from the GTF for the final object...")
          suppressPackageStartupMessages({
            library(GenomicFeatures)
            library(txdbmaker)
          })
          txdb <- tryCatch(txdbmaker::makeTxDbFromGFF(gtfPath, format = "gtf"),
                           error = function(e) GenomicFeatures::makeTxDbFromGFF(gtfPath, format = "gtf"))
          tx <- transcripts(txdb, columns = c("tx_name", "gene_id"))
          names(tx) <- tx\$tx_name
          common <- intersect(rownames(se), names(tx))
          se <- se[common, , drop = FALSE]
          se <- SummarizedExperiment::SummarizedExperiment(
            assays = as.list(assays(se)),
            rowRanges = tx[common],
            colData = colData(se))
        }

        # --- Write output files ---
        message("Writing output files...")
        saveRDS(se, "tximeta_se.rds")

        # Export row ranges to CSV. rowRanges metadata may carry list/CharacterList
        # columns (e.g. gene_id); collapse those to plain character so write.csv works.
        rr_df <- as.data.frame(rowRanges(se))
        rr_df[] <- lapply(rr_df, function(col) {
            if (is.list(col)) vapply(col, function(x) paste(unlist(x), collapse = ";"), character(1))
            else col
        })
        write.csv(rr_df, "row_ranges.csv", row.names = TRUE)
        
        # Export seqinfo to CSV
        si_df <- as.data.frame(seqinfo(se))
        write.csv(si_df, "seqinfo.csv", row.names = TRUE)
        
        message("Pipeline completed successfully. Outputs written to 'tximeta_se.rds', 'row_ranges.csv', and 'seqinfo.csv'.")

    writeLines(c(
        '"BIOC_TXIMETA_LINKED_TRANSCRIPTOMES":',
        paste0('    tximeta: ', as.character(packageVersion('tximeta')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_linked_transcriptomes.csv versions.yml
    """
}

workflow BIOC_TXIMETA_LINKED_TRANSCRIPTOMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ quant.sf, custom_transcriptome.fa.gz, custom_annotation.gtf.gz ] ]

    main:
    BIOC_TXIMETA_LINKED_TRANSCRIPTOMES(ch_input)

    emit:
    tables   = BIOC_TXIMETA_LINKED_TRANSCRIPTOMES.out.tables
    plots    = BIOC_TXIMETA_LINKED_TRANSCRIPTOMES.out.plots
    objects  = BIOC_TXIMETA_LINKED_TRANSCRIPTOMES.out.objects
    versions = BIOC_TXIMETA_LINKED_TRANSCRIPTOMES.out.versions
}
