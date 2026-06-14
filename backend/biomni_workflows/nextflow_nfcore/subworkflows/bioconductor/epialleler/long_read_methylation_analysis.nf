#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epialleler — long_read_methylation_analysis
// Preprocess long-read BAM files (with MM/ML tags) and generate cytosine-level reports and methylation patterns.
// Input: longread.bam, long.bed
// Container: quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0
// R packages: GenomicRanges, epialleleR, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-epialleler:1.18.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicRanges", "epialleleR", "rtracklayer")
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
    library(epialleleR)
    library(rtracklayer)
    library(GenomicRanges)
    
    # --- Load the target region (long.bed) ---
    # Robust loading: try RDS first, then BED import
    if (file.exists("long.bed")) {
      long.bed <- tryCatch({
        readRDS("long.bed")
      }, error = function(e) {
        rtracklayer::import("long.bed")
      })
    } else {
      stop("Required input file 'long.bed' not found in the working directory.")
    }
    
    # Verify BAM file exists
    if (!file.exists("longread.bam")) {
      stop("Required input file 'longread.bam' not found in the working directory.")
    }
    
    # --- Preprocess long-read BAM using preprocessBam with quality ---
    message("Preprocessing long-read BAM...")
    longread.data <- preprocessBam("longread.bam", min.mapq=30, min.baseq=20, min.prob=178)
    
    # --- Generate cytosine-level report using ---
    message("Generating cytosine report...")
    cytosine.report <- generateCytosineReport(longread.data, threshold.reads=FALSE)
    
    # Save cytosine report
    write.csv(cytosine.report, "cytosine_report.csv", row.names=FALSE)
    message("Cytosine report saved to 'cytosine_report.csv'.")
    
    # --- Extract and plot methylation patterns using ---
    message("Preprocessing BAM with target regions...")
    long.bam <- "longread.bam"
    long.data <- preprocessBam(bam=long.bam, targets=long.bed, clip.to.targets=TRUE, min.mapq=30, min.baseq=20, min.prob=178)
    
    message("Extracting methylation patterns...")
    patterns <- extractPatterns(bam=long.data, bed=long.bed)
    
    # Save patterns object
    saveRDS(patterns, "extracted_patterns.rds")
    message("Extracted patterns saved to 'extracted_patterns.rds'.")
    
    # Plot patterns to PDF
    message("Plotting patterns...")
    pdf("methylation_patterns.pdf", width=10, height=6)
    plotPatterns(patterns, npatterns.per.bin=Inf)
    dev.off()
    message("Methylation patterns plot saved to 'methylation_patterns.pdf'.")

    writeLines(c(
        '"BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS":',
        paste0('        epialleler: ', as.character(packageVersion("epialleler")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_long_read_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ longread.bam, long.bed ] ]

    main:
    BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_EPIALLELER_LONG_READ_METHYLATION_ANALYSIS.out.versions
}
