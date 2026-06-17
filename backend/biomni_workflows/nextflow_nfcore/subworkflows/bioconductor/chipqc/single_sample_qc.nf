#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChIPQC — single_sample_qc
// Assess quality metrics for a single ChIP-seq BAM file and its associated peak file.
// Input: reads/SRR568129.bam, peaks/SRR568129_chr22_peaks.bed
// Container: quay.io/biocontainers/bioconductor-chipqc:1.42.0--r44hdfd78af_0
// R packages: ChIPQC
// Bioconductor: 3.20 | R: 4.4
// Requires: ChIPQC
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run ChIPQCsample to compute metrics for the single sample
//  * 2. [Core Analysis] Retrieve metrics using QCmetrics
//  * 3. [Visualization & Output] Plot cross-coverage using plotCC

nextflow.enable.dsl = 2

process BIOC_CHIPQC_SINGLE_SAMPLE_QC {
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
    .bm_deps <- c("ChIPQC")
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
    
    # Check for required input files
    input_bam <- "reads/SRR568129.bam"
    input_bed <- "peaks/SRR568129_chr22_peaks.bed"
    
    if (!file.exists(input_bam)) {
      stop(paste("Required input BAM file missing:", input_bam))
    }
    if (!file.exists(input_bed)) {
      stop(paste("Required input BED file missing:", input_bed))
    }
    
    # Load the ChIPQC library
    library(ChIPQC)
    
    # 1. Run ChIPQCsample to compute metrics for the single sample
    # Using the exact function call and arguments from the documented code
    CTCF1 = ChIPQCsample("reads/SRR568129.bam", peaks="peaks/SRR568129_chr22_peaks.bed")
    
    # Print the object summary to console
    print(CTCF1)
    
    # 2. Retrieve metrics using QCmetrics
    metrics <- QCmetrics(CTCF1)
    print(metrics)
    
    # Save the retrieved metrics to a CSV file
    write.csv(as.data.frame(t(metrics)), "CTCF1_QCmetrics.csv", row.names = TRUE)
    
    # 3. Plot cross-coverage using plotCC
    pdf("CTCF1_plotCC.pdf", width = 7, height = 7)
    plotCC(CTCF1)
    dev.off()
    
    # Save the constructed ChIPQCsample object as an RDS file for downstream use
    saveRDS(CTCF1, "CTCF1_ChIPQCsample.rds")

    writeLines(c(
        '"BIOC_CHIPQC_SINGLE_SAMPLE_QC":',
        paste0('    ChIPQC: ', as.character(packageVersion('ChIPQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_qc.csv versions.yml
    """
}

workflow BIOC_CHIPQC_SINGLE_SAMPLE_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reads/SRR568129.bam, peaks/SRR568129_chr22_peaks.bed ] ]

    main:
    BIOC_CHIPQC_SINGLE_SAMPLE_QC(ch_input)

    emit:
    tables   = BIOC_CHIPQC_SINGLE_SAMPLE_QC.out.tables
    plots    = BIOC_CHIPQC_SINGLE_SAMPLE_QC.out.plots
    objects  = BIOC_CHIPQC_SINGLE_SAMPLE_QC.out.objects
    versions = BIOC_CHIPQC_SINGLE_SAMPLE_QC.out.versions
}
