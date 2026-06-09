#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nucleR — mnase_bias_correction
// Correct nucleosomal DNA coverage profiles using a mock control of naked DNA digested with MNase.
// Input: nucleosome_reads.bam, control_reads.bam
// Container: quay.io/biocontainers/bioconductor-nucler:2.42.0--r45hdfd78af_0
// Requires: GenomicRanges, IRanges, ggplot2, nucleR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Generate or load experimental and control coverages
//  * 2. [Core Analysis] Correct the experimental coverage using controlCorrection

nextflow.enable.dsl = 2

process BIOC_NUCLER_MNASE_BIAS_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(nucleR)
    library(GenomicRanges)
    library(IRanges)
    library(ggplot2)
    
    # 1. Load experimental and control coverages from BAM files
    message("Reading input BAM files...")
    exp_reads <- tryCatch({
      readBAM("nucleosome_reads.bam", type="paired")
    }, error = function(e) {
      message("Failed to read as paired-end, trying single-end...")
      readBAM("nucleosome_reads.bam", type="single")
    })
    
    ctr_reads <- tryCatch({
      readBAM("control_reads.bam", type="paired")
    }, error = function(e) {
      message("Failed to read as paired-end, trying single-end...")
      readBAM("control_reads.bam", type="single")
    })
    
    # Generate coverages
    exp <- coverage(exp_reads)
    ctr <- coverage(ctr_reads)
    
    # 2. Correct the experimental coverage using controlCorrection
    message("Applying MNase bias correction...")
    corrected <- controlCorrection(exp, ctr)
    
    # Save results
    message("Saving results...")
    saveRDS(corrected, "corrected_coverage.rds")
    
    # Export to WIG format
    tryCatch({
      export.wig(corrected, "corrected_coverage.wig")
    }, error = function(e) {
      message("Could not export to WIG: ", e\$message)
    })
    
    # Generate a plot for the first chromosome (first 10,000 bp)
    tryCatch({
      chr <- names(exp)[1]
      max_len <- min(10000, length(exp[[chr]]), length(corrected[[chr]]))
      
      exp_sub <- as.vector(exp[[chr]])[1:max_len]
      corrected_sub <- as.vector(corrected[[chr]])[1:max_len]
      
      plot_data <- rbind(
          data.frame(
              position = 1:max_len,
              coverage = exp_sub,
              type = "Uncorrected"
          ),
          data.frame(
              position = 1:max_len,
              coverage = corrected_sub,
              type = "Corrected"
          )
      )
      
      p <- ggplot(plot_data, aes(x = position, y = coverage, color = type)) +
          geom_line(alpha = 0.8) +
          theme_minimal() +
          labs(
              title = paste("MNase Bias Correction - Chromosome", chr),
              x = "Genomic Position",
              y = "Coverage",
              color = "Status"
          ) +
          theme(legend.position = "bottom")
      
      ggsave("mnase_correction_plot.pdf", plot = p, width = 8, height = 4)
      message("Plot saved to mnase_correction_plot.pdf")
    }, error = function(e) {
      message("Could not generate plot: ", e\$message)
    })
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_NUCLER_MNASE_BIAS_CORRECTION":',
        paste0('    nucleR: ', as.character(packageVersion('nucleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mnase_bias_correction.csv versions.yml
    """
}

workflow BIOC_NUCLER_MNASE_BIAS_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nucleosome_reads.bam, control_reads.bam ] ]

    main:
    BIOC_NUCLER_MNASE_BIAS_CORRECTION(ch_input)

    emit:
    tables   = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.tables
    plots    = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.plots
    objects  = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.objects
    versions = BIOC_NUCLER_MNASE_BIAS_CORRECTION.out.versions
}
