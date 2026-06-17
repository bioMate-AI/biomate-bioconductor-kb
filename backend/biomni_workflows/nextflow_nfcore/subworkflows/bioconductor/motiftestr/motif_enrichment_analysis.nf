#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifTestR — motif_enrichment_analysis
// Test for overall enrichment of motifs in a set of test sequences compared to a genomic-feature-matched background control set.
// Input: ar_er_peaks, zr75_enh, hg19_mask, BSgenome.Hsapiens.UCSC.hg19, ex_pfm
// Container: quay.io/biocontainers/bioconductor-motiftestr:1.6.1--r45hdfd78af_0
// R packages: BSgenome, BSgenome.Hsapiens.UCSC.hg19, Biostrings, GenomicRanges, motifTestR
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BSgenome.Hsapiens.UCSC.hg19, Biostrings, GenomicRanges, motifTestR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Annotate peaks by genomic features
//  * 2. [Input & Preparation] Define background ranges using GRangesList
//  * 3. [Core Analysis] Generate randomly-selected, size-matched background ranges using makeRMRanges()
//  * 4. [Core Analysis] Extract background sequences using getSeq()
//  * 5. [Core Analysis] Test for motif enrichment using testMotifEnrich() with quasi or iteration models

nextflow.enable.dsl = 2

process BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS {
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
    .bm_deps <- c("BSgenome", "BSgenome.Hsapiens.UCSC.hg19", "Biostrings", "GenomicRanges", "motifTestR")
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
        library(motifTestR)
        library(GenomicRanges)
        library(Biostrings)
        library(BSgenome)
        
        # 1. Load User Inputs from the working directory
        message("Loading input files...")
        ar_er_peaks <- readRDS("ar_er_peaks.rds")
        zr75_enh <- readRDS("zr75_enh.rds")
        hg19_mask <- readRDS("hg19_mask.rds")
        ex_pfm <- readRDS("ex_pfm.rds")
        
        if (file.exists("BSgenome.Hsapiens.UCSC.hg19.rds")) {
          BSgenome.Hsapiens.UCSC.hg19 <- readRDS("BSgenome.Hsapiens.UCSC.hg19.rds")
        } else {
          library(BSgenome.Hsapiens.UCSC.hg19)
        }
        
        # Define parameters
        cores <- 1
        score_thresh <- "70%"
        sq <- seqinfo(ar_er_peaks)
        
        # Generate test_seq (as done in vignette)
        message("Generating test sequences...")
        test_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, ar_er_peaks)
        names(test_seq) <- as.character(ar_er_peaks)
        
        # Stage 1: Annotate peaks by genomic features
        message("Annotating peaks by genomic features...")
        ar_er_peaks\$feature <- ifelse(
          overlapsAny(ar_er_peaks, zr75_enh), "enhancer", "other"
        )
        
        # Stage 2: Define background ranges using GRangesList
        message("Defining background ranges...")
        all_chr <- GRanges(sq)
        bg_ranges <- GRangesList(
          enhancer = zr75_enh,
          other = GenomicRanges::setdiff(all_chr, zr75_enh)
        )
        
        # Stage 3: Generate randomly-selected, size-matched background ranges using makeRMRanges()
        message("Generating size-matched background ranges...")
        set.seed(305)
        rm_ranges <- makeRMRanges(
          splitAsList(ar_er_peaks, ar_er_peaks\$feature),
          bg_ranges, exclude = hg19_mask,
          n_iter = 100
        )
        
        # Stage 4: Extract background sequences using getSeq()
        message("Extracting background sequences...")
        rm_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, rm_ranges)
        mcols(rm_seq) <- mcols(rm_ranges)
        
        # Stage 5: Test for motif enrichment using testMotifEnrich() with quasi or iteration models
        message("Testing for motif enrichment (quasi model)...")
        enrich_res <- testMotifEnrich(
          ex_pfm, test_seq, rm_seq, min_score = score_thresh, model = "quasi", mc.cores = cores
        )
        
        message("Testing for motif enrichment (iteration model)...")
        iter_res <- testMotifEnrich(
          ex_pfm, test_seq, rm_seq, min_score = score_thresh, mc.cores = cores, model = "iteration"
        )
        
        # Write outputs
        message("Writing output files...")
        write.csv(as.data.frame(enrich_res), "enrich_res_quasi.csv", row.names = TRUE)
        write.csv(as.data.frame(iter_res), "enrich_res_iteration.csv", row.names = TRUE)
        saveRDS(enrich_res, "enrich_res_quasi.rds")
        saveRDS(iter_res, "enrich_res_iteration.rds")
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS":',
        paste0('    motifTestR: ', as.character(packageVersion('motifTestR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ar_er_peaks, zr75_enh, hg19_mask, BSgenome.Hsapiens.UCSC.hg19, ex_pfm ] ]

    main:
    BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_MOTIFTESTR_MOTIF_ENRICHMENT_ANALYSIS.out.versions
}
