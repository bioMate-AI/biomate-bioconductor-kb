#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rGADEM — de_novo_motif_discovery
// Identify novel sequence motifs from genomic peak regions using rGADEM and a reference genome.
// Input: peaks.bed
// Container: quay.io/biocontainers/bioconductor-rgadem:2.54.0--r44h3df3fcb_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, rGADEM, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import peak coordinates as a GRanges object
//  * 2. [Input & Preparation] Load the matching BSgenome reference genome
//  * 3. [Core Analysis] Run the GADEM analysis to discover motifs
//  * 4. [Core Analysis] Query the resulting gadem object for identified motifs and consensus sequences

nextflow.enable.dsl = 2

process BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("rGADEM", "BSgenome.Hsapiens.UCSC.hg19", "rtracklayer")
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
        library(rGADEM)
        library(BSgenome.Hsapiens.UCSC.hg19)
        library(rtracklayer)
        
        # 1. Import peak coordinates as a GRanges object
        if (!file.exists("peaks.bed")) {
          stop("Error: Input file 'peaks.bed' not found in the working directory.")
        }
        
        peaks <- rtracklayer::import("peaks.bed", format = "bed")
        
        # 2. Run the GADEM analysis to discover motifs
        # (Using the exact documented function call and arguments)
        gadem <- GADEM(peaks, genome = Hsapiens, verbose = 1)
        
        # 3. Query the resulting gadem object for identified motifs and consensus sequences
        n_motifs <- nMotifs(gadem)
        consensus_seqs <- consensus(gadem)
        
        # 4. Write named output files for the results
        # Save the complete GADEM object
        saveRDS(gadem, file = "gadem_analysis_results.rds")
        
        # Save the discovered motifs and their consensus sequences to a CSV file
        motifs_df <- data.frame(
          Motif_Index = seq_len(n_motifs),
          Consensus_Sequence = consensus_seqs,
          stringsAsFactors = FALSE
        )
        write.csv(motifs_df, file = "discovered_motifs.csv", row.names = FALSE)
        
        # Save a text summary of the run
        summary_text <- c(
          "rGADEM De Novo Motif Discovery Summary",
          "======================================",
          paste("Input Peaks Analyzed :", length(peaks)),
          paste("Motifs Discovered    :", n_motifs)
        )
        writeLines(summary_text, con = "gadem_summary.txt")

    writeLines(c(
        '"BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY":',
        paste0('    rGADEM: ', as.character(packageVersion('rGADEM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_novo_motif_discovery.csv versions.yml
    """
}

workflow BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.bed ] ]

    main:
    BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY.out.tables
    plots    = BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY.out.plots
    objects  = BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY.out.objects
    versions = BIOC_RGADEM_DE_NOVO_MOTIF_DISCOVERY.out.versions
}
