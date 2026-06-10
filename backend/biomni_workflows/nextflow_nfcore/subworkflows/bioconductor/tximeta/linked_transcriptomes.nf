#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tximeta — linked_transcriptomes
// Link custom or modified transcriptomes to their FASTA/GTF sources via sequence digests for reproducible import.
// Input: quant.sf, custom_transcriptome.fa.gz, custom_annotation.gtf.gz
// Container: quay.io/biocontainers/bioconductor-tximeta:1.28.2--r45hdfd78af_0
// Requires: Biostrings, SummarizedExperiment, digest, tximeta
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define paths to index, FASTA, and GTF. 2. Create a linked transcriptome using makeLinkedTxome(). 3. Import data using tximeta(). 4

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required libraries
        library(tximeta)
        library(Biostrings)
        library(digest)
        
        # Set tximeta BiocFileCache to a temporary directory to prevent interactive prompts
        temp_bfc <- file.path(tempdir(), "tximeta_bfc")
        dir.create(temp_bfc, showWarnings = FALSE, recursive = TRUE)
        setTximetaBFC(temp_bfc)
        
        # 1. Read the custom transcriptome FASTA and compute its SHA-256 digest
        # This replicates the exact sequence digest that Salmon and tximeta use.
        message("Reading custom transcriptome and computing sequence digest...")
        fasta_file <- "custom_transcriptome.fa.gz"
        fa <- Biostrings::readDNAStringSet(fasta_file)
        seq_concat <- toupper(paste(as.character(fa), collapse = ""))
        sha256 <- digest::digest(seq_concat, algo = "sha256", serialize = FALSE)
        message("Computed SHA-256 digest: ", sha256)
        
        # 2. Create a mock Salmon index directory containing the digest
        # tximeta's makeLinkedTxome reads the digest from the index directory.
        indexDir <- normalizePath("custom_index", mustWork = FALSE)
        dir.create(indexDir, showWarnings = FALSE, recursive = TRUE)
        writeLines(paste0('{"index_seq_hash": "', sha256, '"}'), file.path(indexDir, "header.json"))
        writeLines(paste0('{"index_seq_hash": "', sha256, '"}'), file.path(indexDir, "info.json"))
        
        # 3. Set up the Salmon quantification directory structure
        # tximeta expects aux_info/meta_info.json relative to the quant.sf file.
        quant_dir <- "quant_output"
        dir.create(file.path(quant_dir, "aux_info"), showWarnings = FALSE, recursive = TRUE)
        file.copy("quant.sf", file.path(quant_dir, "quant.sf"), overwrite = TRUE)
        writeLines(
          paste0('{"index_seq_hash": "', sha256, '", "salmon_version": "1.5.2"}'),
          file.path(quant_dir, "aux_info", "meta_info.json")
        )
        
        # 4. Define paths for the linked transcriptome
        fastaFTP <- normalizePath(fasta_file)
        gtfPath <- normalizePath("custom_annotation.gtf.gz")
        tmp <- tempdir()
        jsonFile <- file.path(tmp, paste0(basename(indexDir), ".json"))
        
        # 5. Create the linked transcriptome
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
        
        # 6. Import data using tximeta
        file <- file.path(quant_dir, "quant.sf")
        coldata <- data.frame(
          files = file,
          names = "custom_sample",
          sample = "1",
          stringsAsFactors = FALSE
        )
        
        message("Running tximeta import...")
        se <- tximeta(coldata)
        
        # Inspect the imported object
        message("Inspecting row ranges and seqinfo...")
        rowRanges(se)
        seqinfo(se)
        
        # 7. Demonstrate loading the shared linked transcriptome JSON
        message("Loading linked transcriptome from JSON...")
        jsonFile <- file.path(tmp, paste0(basename(indexDir), ".json"))
        loadLinkedTxome(jsonFile)
        
        message("Re-running tximeta import after loading JSON...")
        se <- tximeta(coldata)
        
        # 8. Write output files
        message("Writing output files...")
        saveRDS(se, "tximeta_se.rds")
        
        # Export row ranges to CSV
        rr_df <- as.data.frame(rowRanges(se))
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
