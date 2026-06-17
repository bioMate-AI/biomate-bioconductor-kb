#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CSAR — chip_seq_peak_calling_and_annotation
// Identify protein-bound genomic regions from ChIP-seq data, map them to genes, and calculate FDR thresholds using permutation.
// Input: sample_reads.tsv, control_reads.tsv, genes.gff
// Container: quay.io/biocontainers/bioconductor-csar:1.62.0--r45h01b2380_0
// R packages: CSAR
// Bioconductor: 3.20 | R: 4.4
// Requires: CSAR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Calculate extended read overlaps per nucleotide using mappedReads2Nhits
//  * 2. [Input & Preparation] Calculate read-enrichment scores using ChIPseqScore
//  * 3. [Core Analysis] Identify candidate enriched regions using sigWin
//  * 4. [Visualization & Output] Export scores to WIG format using score2wig
//  * 5. [Core Analysis] Calculate distance of candidate regions to genes using distance2Genes
//  * 6. [Core Analysis] Identify genes with peaks using genesWithPeaks
//  * 7. [Core Analysis] Generate permutated datasets and calculate permutated window scores using permutatedWinScores
//  * 8. [Input & Preparation] Load permutated scores using getPermutatedWinScores
//  * 9. [Core Analysis] Calculate FDR threshold using getThreshold

nextflow.enable.dsl = 2

process BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION {
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
    .bm_deps <- c("CSAR")
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
        
    # Load required library
    library(CSAR)
    
    # Read user input files from the working directory
    sampleSEP3_test <- read.delim("sample_reads.tsv", header = TRUE, stringsAsFactors = FALSE)
    controlSEP3_test <- read.delim("control_reads.tsv", header = TRUE, stringsAsFactors = FALSE)
    TAIR8_genes_test <- read.delim("genes.gff", header = TRUE, stringsAsFactors = FALSE)
    
    # Dynamically determine the list of chromosomes and their lengths from the input datasets
    all_chr <- c(sampleSEP3_test\$chr, controlSEP3_test\$chr)
    all_pos <- c(sampleSEP3_test\$pos + sampleSEP3_test\$lengthRead, controlSEP3_test\$pos + controlSEP3_test\$lengthRead)
    chr_lengths_tapply <- tapply(all_pos, all_chr, max, na.rm = TRUE)
    chr_names <- names(chr_lengths_tapply)
    # Add a buffer of 1000bp to account for the virtual read extension (default 300bp)
    chr_lengths <- as.numeric(chr_lengths_tapply) + 1000
    
    # 1. Calculate extended read overlaps per nucleotide using mappedReads2Nhits
    nhitsS<-mappedReads2Nhits(sampleSEP3_test,file="sampleSEP3_test",chr=chr_names,chrL=chr_lengths)
    nhitsC<-mappedReads2Nhits(controlSEP3_test,file="controlSEP3_test",chr=chr_names,chrL=chr_lengths)
    nhitsC\$filenames
    nhitsS\$filenames
    
    # 2. Calculate read-enrichment scores using ChIPseqScore
    test<-ChIPseqScore(control=nhitsC,sample=nhitsS,file="test",times=10000)
    test\$filenames
    
    # 3. Identify candidate enriched regions using sigWin
    win<-sigWin(test)
    head(win)
    
    # 4. Export scores to WIG format using score2wig
    score2wig(test,file="test.wig",times=10000)
    
    # 5. Calculate distance of candidate regions to genes using distance2Genes
    d<-distance2Genes(win=win,gff=TAIR8_genes_test)
    d
    
    # 6. Identify genes with peaks using genesWithPeaks
    genes<-genesWithPeaks(d)
    head(genes)
    
    # 7. Generate permutated datasets and calculate permutated window scores using permutatedWinScores
    permutatedWinScores(nn=1,sample=sampleSEP3_test,control=controlSEP3_test,fileOutput="test",chr=chr_names,chrL=chr_lengths)
    permutatedWinScores(nn=2,sample=sampleSEP3_test,control=controlSEP3_test,fileOutput="test",chr=chr_names,chrL=chr_lengths)
    
    # 8. Load permutated scores using getPermutatedWinScores
    nulldist<-getPermutatedWinScores(file="test",nn=1:2)
    
    # 9. Calculate FDR threshold using getThreshold
    threshold_results <- getThreshold(winscores=values(win)\$score,permutatedScores=nulldist,FDR=.05)
    threshold_results
    
    # Save meaningful results to output files
    write.csv(as.data.frame(win), "sig_windows.csv", row.names = FALSE)
    saveRDS(win, "sig_windows.rds")
    write.csv(d, "distance_to_genes.csv", row.names = FALSE)
    write.csv(genes, "genes_with_peaks.csv", row.names = FALSE)
    write.csv(as.data.frame(threshold_results), "fdr_threshold_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION":',
        paste0('    CSAR: ', as.character(packageVersion('CSAR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chip_seq_peak_calling_and_annotation.csv versions.yml
    """
}

workflow BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_reads.tsv, control_reads.tsv, genes.gff ] ]

    main:
    BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.tables
    plots    = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.plots
    objects  = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.objects
    versions = BIOC_CSAR_CHIP_SEQ_PEAK_CALLING_AND_ANNOTATION.out.versions
}
