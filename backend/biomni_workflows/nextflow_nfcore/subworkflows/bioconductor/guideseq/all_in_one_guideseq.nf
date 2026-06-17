#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: guideseq — all_in_one_guideseq
// Run the entire GUIDE-seq analysis workflow (from UMI deduplication to off-target analysis) in a single function call.
// Input: bowtie2.HEK293_site4_chr13.sort.bam, UMI-HEK293_site4_chr13.txt, gRNA.fa
// Container: quay.io/biocontainers/bioconductor-guideseq:1.40.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, GUIDEseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-guideseq:1.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "GUIDEseq")
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
    library(GUIDEseq)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Define input file paths from the working directory
    bamfile <- "bowtie2.HEK293_site4_chr13.sort.bam"
    umifile <- "UMI-HEK293_site4_chr13.txt"
    gRNA.file <- "gRNA.fa"
    
    # Verify that the required input files exist
    if (!file.exists(bamfile)) {
        stop(paste("Required BAM file not found:", bamfile))
    }
    if (!file.exists(umifile)) {
        stop(paste("Required UMI file not found:", umifile))
    }
    if (!file.exists(gRNA.file)) {
        stop(paste("Required gRNA FASTA file not found:", gRNA.file))
    }
    
    # Run the complete GUIDE-seq analysis workflow
    message("Running GUIDEseqAnalysis...")
    guideSeqRes <- GUIDEseqAnalysis(
        alignment.inputfile = bamfile, 
        umi.inputfile = umifile, 
        gRNA.file = gRNA.file, 
        orderOfftargetsBy = "peak_score",
        descending = TRUE, 
        n.cores.max = 1,
        BSgenomeName = Hsapiens, 
        min.reads = 1
    )
    
    # Print the names of the resulting list elements
    print(names(guideSeqRes))
    
    # Save the complete results object as an RDS file
    message("Saving results to guideSeqRes.rds...")
    saveRDS(guideSeqRes, file = "guideSeqRes.rds")
    
    # Export meaningful tables to CSV files
    if (!is.null(guideSeqRes\$offTargets)) {
        message("Saving off-targets to offTargets.csv...")
        write.csv(as.data.frame(guideSeqRes\$offTargets), file = "offTargets.csv", row.names = FALSE)
    }
    
    if (!is.null(guideSeqRes\$merged.peaks)) {
        message("Saving merged peaks to merged_peaks.csv...")
        write.csv(as.data.frame(guideSeqRes\$merged.peaks), file = "merged_peaks.csv", row.names = FALSE)
    }
    
    if (!is.null(guideSeqRes\$peaks)) {
        message("Saving peaks to peaks.csv...")
        write.csv(as.data.frame(guideSeqRes\$peaks), file = "peaks.csv", row.names = FALSE)
    }
    
    if (!is.null(guideSeqRes\$read.summary)) {
        message("Saving read summary to read_summary.csv...")
        write.csv(as.data.frame(guideSeqRes\$read.summary), file = "read_summary.csv", row.names = FALSE)
    }
    
    message("GUIDE-seq analysis pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ":',
        paste0('        guideseq: ', as.character(packageVersion("guideseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_all_in_one_guideseq.csv versions.yml
    """
}

workflow BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bowtie2.HEK293_site4_chr13.sort.bam, UMI-HEK293_site4_chr13.txt, gRNA.fa ] ]

    main:
    BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ(ch_input)

    emit:
    tables   = BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ.out.tables
    plots    = BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ.out.plots
    objects  = BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ.out.objects
    versions = BIOC_GUIDESEQ_ALL_IN_ONE_GUIDESEQ.out.versions
}
