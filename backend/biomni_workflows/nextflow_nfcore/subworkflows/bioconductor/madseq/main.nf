#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: madseq — mosaic_aneuploidy_detection
// Detect, classify, and quantify mosaic aneuploidy from BAM and VCF files using a Bayesian framework.
// Input: sample.bam, sample.vcf
// Container: quay.io/biocontainers/bioconductor-madseq:1.32.0--r44hdfd78af_0
// R packages: knitr, madseq
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-madseq:1.32.0--r44hdfd78af_0"

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
    .bm_deps <- c("knitr", "madseq")
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
    if (!requireNamespace("madseq", quietly = TRUE)) {
      stop("Package 'madseq' is required but not installed.")
    }
    library(madseq)
    
    # Define input files
    bam_file <- "sample.bam"
    vcf_file <- "sample.vcf"
    
    # Check if input files exist in the working directory
    if (!file.exists(bam_file)) {
      stop(paste("Required BAM file not found in working directory:", bam_file))
    }
    if (!file.exists(vcf_file)) {
      stop(paste("Required VCF file not found in working directory:", vcf_file))
    }
    
    # --- Prepare coverage bins ---
    message("Preparing coverage bins...")
    md <- prepareCoverageBin(bam_file = bam_file, bin_size = 100000, genome = "hg19")
    
    # --- Run the mosaic aneuploidy detection model ---
    message("Running MadSeq model...")
    res <- runMadSeq(
      bam_file = bam_file,
      vcf_file = vcf_file,
      target_chr = "chr21",
      md = md,
      model = "all",
      steps = 10000
    )
    
    # Save the primary S4 object and text summary
    message("Saving results...")
    saveRDS(res, file = "madseq_results.rds")
    
    sink("madseq_summary.txt")
    show(res)
    sink()
    
    # --- Plot the posterior distribution of the mosaic fraction ---
    message("Generating fraction plot...")
    pdf("plot_fraction.pdf", width = 7, height = 5)
    plotFraction(res)
    dev.off()
    
    # --- Plot the coverage and BAF data with the model fit ---
    message("Generating MadSeq plot...")
    pdf("plot_madseq.pdf", width = 10, height = 7)
    plotMadSeq(res)
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved: madseq_results.rds, madseq_summary.txt, plot_fraction.pdf, plot_madseq.pdf")

    writeLines(c(
        '"BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION":',
        paste0('        madseq: ', as.character(packageVersion("madseq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosaic_aneuploidy_detection.csv versions.yml
    """
}

workflow BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.bam, sample.vcf ] ]

    main:
    BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION(ch_input)

    emit:
    tables   = BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION.out.tables
    plots    = BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION.out.plots
    objects  = BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION.out.objects
    versions = BIOC_MADSEQ_MOSAIC_ANEUPLOIDY_DETECTION.out.versions
}
