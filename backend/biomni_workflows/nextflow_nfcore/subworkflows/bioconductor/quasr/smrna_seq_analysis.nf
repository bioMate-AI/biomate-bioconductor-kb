#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QuasR — smrna_seq_analysis
// Preprocess small RNA reads to remove adapters, align allowing multi-mapping, and quantify mature and primary miRNAs.
// Input: samples_mirna.txt, hg19sub.fa, mirbaseXX_qsr.gff3
// Container: quay.io/biocontainers/bioconductor-quasr:1.50.0--r45ha27e39d_0
// R packages: GenomicRanges, QuasR, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, QuasR, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Remove 3' adapters using preprocessReads
//  * 2. [Core Analysis] Align reads allowing multi-mapping using qAlign with maxHits=50
//  * 3. [Input & Preparation] Import miRNA annotations
//  * 4. [Core Analysis] Quantify mature and primary miRNAs using qCount

nextflow.enable.dsl = 2

process BIOC_QUASR_SMRNA_SEQ_ANALYSIS {
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
    .bm_deps <- c("GenomicRanges", "QuasR", "rtracklayer")
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
    
    library(QuasR)
    library(rtracklayer)
    library(GenomicRanges)
    
    # Define input files from the working directory
    sampleFile <- "samples_mirna.txt"
    genomeFile <- "hg19sub.fa"
    gffFile <- "mirbaseXX_qsr.gff3"
    
    # Prepare sample file with processed reads filenames
    sampleFile2 <- sub(".txt", "_processed.txt", sampleFile)
    
    tab <- read.delim(sampleFile, header = TRUE, as.is = TRUE)
    tab2 <- tab
    tab2\$FileName <- sub(".fa", "_processed.fa", tab\$FileName)
    write.table(tab2, sampleFile2, sep = "\t", quote = FALSE, row.names = FALSE)
    
    # Remove adapters using preprocessReads
    oldwd <- setwd(dirname(sampleFile))
    res <- preprocessReads(tab\$FileName,
                           tab2\$FileName,
                           Rpattern = "TGGAATTCTCGGGTGCCAAGG")
    setwd(oldwd)
    
    # Save preprocessing statistics
    write.csv(res, "preprocessing_stats.csv", row.names = TRUE)
    
    # Align reads allowing multi-mapping (maxHits = 50)
    proj3 <- qAlign(sampleFile2, genomeFile, maxHits = 50)
    
    # Get and save alignment statistics
    stats <- alignmentStats(proj3)
    write.csv(stats, "alignment_stats.csv", row.names = TRUE)
    
    # Import miRNA annotations
    mirs <- import("mirbaseXX_qsr.gff3")
    names(mirs) <- mirs\$Name
    preMirs <- mirs[ mirs\$type == "miRNA_primary_transcript" ]
    matureMirs <- mirs[ mirs\$type == "miRNA" ]
    
    # Quantify mature miRNAs
    matureMirsExtended <- resize(matureMirs, width = 1L, fix = "start") + 3L
    cnt_mature <- qCount(proj3, matureMirsExtended, orientation = "same")
    write.csv(cnt_mature, "mature_mirna_counts.csv", row.names = TRUE)
    
    # Quantify primary miRNAs
    cnt_pre <- qCount(proj3, preMirs, orientation = "same")
    write.csv(cnt_pre, "primary_mirna_counts.csv", row.names = TRUE)
    
    # Save the qProject object for downstream analysis
    saveRDS(proj3, "qProject_mirna.rds")

    writeLines(c(
        '"BIOC_QUASR_SMRNA_SEQ_ANALYSIS":',
        paste0('    QuasR: ', as.character(packageVersion('QuasR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_smrna_seq_analysis.csv versions.yml
    """
}

workflow BIOC_QUASR_SMRNA_SEQ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ samples_mirna.txt, hg19sub.fa, mirbaseXX_qsr.gff3 ] ]

    main:
    BIOC_QUASR_SMRNA_SEQ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_QUASR_SMRNA_SEQ_ANALYSIS.out.tables
    plots    = BIOC_QUASR_SMRNA_SEQ_ANALYSIS.out.plots
    objects  = BIOC_QUASR_SMRNA_SEQ_ANALYSIS.out.objects
    versions = BIOC_QUASR_SMRNA_SEQ_ANALYSIS.out.versions
}
