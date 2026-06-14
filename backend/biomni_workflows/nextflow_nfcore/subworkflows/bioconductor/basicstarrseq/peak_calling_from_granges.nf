#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: basicstarrseq — peak_calling_from_granges
// Call peaks on STARR-seq data starting from pre-loaded GRanges objects.
// Input: smallSTARR.bam, smallInput.bam
// Container: quay.io/biocontainers/bioconductor-basicstarrseq:1.38.0--r45hdfd78af_0
// R packages: BasicSTARRseq, GenomicAlignments, GenomicRanges
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: enrichment plot

nextflow.enable.dsl = 2

process BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES {
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
    .bm_deps <- c("BasicSTARRseq", "GenomicAlignments", "GenomicRanges")
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
    
    # Define input file names in the working directory
    starrseqFileName <- "smallSTARR.bam"
    inputFileName <- "smallInput.bam"
    
    # Verify that the input files exist before proceeding
    if (!file.exists(starrseqFileName)) {
      stop(paste("Required input file missing:", starrseqFileName))
    }
    if (!file.exists(inputFileName)) {
      stop(paste("Required input file missing:", inputFileName))
    }
    
    # --- Read BAM files into GRanges objects ---
    message("Reading alignment pairs from BAM files...")
    starrseqGRanges <- granges(readGAlignmentPairs(starrseqFileName))
    inputGRanges <- granges(readGAlignmentPairs(inputFileName))
    
    # --- Initialize STARRseqData object ---
    message("Initializing STARRseqData object...")
    data <- STARRseqData(sample=starrseqGRanges, control=inputGRanges)
    
    # --- Call peaks using getPeaks ---
    message("Calling peaks...")
    peaks <- getPeaks(data)
    
    # --- Write output files ---
    message("Writing results to output files...")
    
    # Save the GRanges object as an RDS file
    saveRDS(peaks, file = "peaks.rds")
    
    # Convert GRanges to a data frame and save as CSV
    peaks_df <- as.data.frame(peaks)
    write.csv(peaks_df, file = "peaks.csv", row.names = FALSE)
    
    # Generate a diagnostic plot of peak enrichment
    pdf("peaks_enrichment_distribution.pdf", width = 6, height = 6)
    if (nrow(peaks_df) > 0) {
      hist(peaks_df\$enrichment, 
           main = "Distribution of Peak Enrichment", 
           xlab = "Enrichment (STARR-seq / Input)", 
           col = "skyblue", 
           border = "white",
           breaks = 10)
    } else {
      plot.new()
      text(0.5, 0.5, "No peaks detected to plot.", cex = 1.2)
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'peaks.rds', 'peaks.csv', and 'peaks_enrichment_distribution.pdf'.")

    writeLines(c(
        '"BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES":',
        paste0('        basicstarrseq: ', as.character(packageVersion("basicstarrseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_calling_from_granges.csv versions.yml
    """
}

workflow BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ smallSTARR.bam, smallInput.bam ] ]

    main:
    BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES(ch_input)

    emit:
    tables   = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES.out.tables
    plots    = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES.out.plots
    objects  = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES.out.objects
    versions = BIOC_BASICSTARRSEQ_PEAK_CALLING_FROM_GRANGES.out.versions
}
