#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: basicstarrseq — peak_calling_from_bam
// Initialize STARR-seq data objects directly from BAM files for paired-end or single-end experiments.
// Input: smallSTARR.bam, smallInput.bam
// Container: quay.io/biocontainers/bioconductor-basicstarrseq:1.38.0--r45hdfd78af_0
// R packages: GenomicAlignments, GenomicRanges, BasicSTARRseq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-basicstarrseq:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicAlignments", "GenomicRanges", "BasicSTARRseq")
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
    library(BasicSTARRseq)
    library(GenomicAlignments)
    library(GenomicRanges)
    
    # --- Specify BAM file paths (User Input) ---
    starrseqFileName <- "smallSTARR.bam"
    inputFileName <- "smallInput.bam"
    
    # Verify file existence before proceeding
    if (!file.exists(starrseqFileName)) {
      stop(paste("Error: Required input file missing:", starrseqFileName))
    }
    if (!file.exists(inputFileName)) {
      stop(paste("Error: Required input file missing:", inputFileName))
    }
    
    # --- Initialize STARRseqData object for paired-end or ---
    message("Initializing STARRseqData with pairedEnd=TRUE...")
    data_paired <- STARRseqData(sample=starrseqFileName, control=inputFileName,
                                pairedEnd=TRUE)
    
    message("Initializing STARRseqData with pairedEnd=FALSE...")
    data_single <- STARRseqData(sample=starrseqFileName, control=inputFileName,
                                pairedEnd=FALSE)
    
    # --- Initialize using GRanges and perform Peak Calling ---
    message("Reading alignments and converting to GRanges...")
    starrseqGRanges <- granges(readGAlignmentPairs(starrseqFileName))
    inputGRanges <- granges(readGAlignmentPairs(inputFileName))
    
    message("Initializing STARRseqData from GRanges...")
    data <- STARRseqData(sample=starrseqGRanges, control=inputGRanges)
    
    message("Calling peaks...")
    peaks <- getPeaks(data)
    
    # --- Write outputs to the working directory ---
    message("Writing output files...")
    saveRDS(data_paired, "starrseq_data_paired.rds")
    saveRDS(data_single, "starrseq_data_single.rds")
    saveRDS(data, "starrseq_data_granges.rds")
    saveRDS(peaks, "starrseq_peaks.rds")
    
    # Export peaks as a CSV table
    peaks_df <- as.data.frame(peaks)
    write.csv(peaks_df, "starrseq_peaks.csv", row.names=FALSE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM":',
        paste0('        basicstarrseq: ', as.character(packageVersion("basicstarrseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_calling_from_bam.csv versions.yml
    """
}

workflow BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ smallSTARR.bam, smallInput.bam ] ]

    main:
    BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM(ch_input)

    emit:
    tables   = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM.out.tables
    plots    = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM.out.plots
    objects  = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM.out.objects
    versions = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_BAM.out.versions
}
