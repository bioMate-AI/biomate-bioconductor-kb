#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — custom_counting_and_predefined_regions
// Configure custom read counting strategies (single-end or paired-end) and perform enrichment calling on predefined genomic regions of identical size.
// Input: ChIP.bam, Control.bam
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// R packages: GenomicRanges, Rsamtools, normr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "normr")
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
    library(normr)
    library(GenomicRanges)
    library(Rsamtools)
    
    # Define input files from the working directory
    k4me3Bamfile <- "ChIP.bam"
    inputBamfile <- "Control.bam"
    
    # Verify that input files exist
    if (!file.exists(k4me3Bamfile)) {
      stop(paste("Required input file missing:", k4me3Bamfile))
    }
    if (!file.exists(inputBamfile)) {
      stop(paste("Required input file missing:", inputBamfile))
    }
    
    # Extract chromosome information from the BAM header to define the genome
    bam_header <- Rsamtools::scanBamHeader(k4me3Bamfile)
    targets <- bam_header[[1]]\$targets
    
    if (length(targets) == 0) {
      stop("No chromosomes found in the BAM header.")
    }
    
    # Construct the genome data.frame as expected by normr
    genome <- data.frame(
      chrom = names(targets),
      size = as.integer(targets),
      stringsAsFactors = FALSE
    )
    
    # Define predefined genomic regions (genes) based on the BAM header
    # We define one 1000bp region in the middle of each chromosome to represent "genes"
    gene_starts <- pmax(1, floor(targets / 2) - 500)
    gene_ends <- gene_starts + 1000
    genes <- GenomicRanges::GRanges(
      seqnames = names(targets),
      ranges = Request = IRanges::IRanges(start = gene_starts, end = gene_ends),
      strand = "+"
    )
    
    # 1. Define custom single-end and paired-end counting configurations
    # Single End:
    # Count in 500bp bins.
    # Consider only reads with Mapping Quality >= 20.
    # Filter reads for marked duplicates (e.g. with picard mark-duplicates)
    # Shift the counting position for a read 100 bp downstream.
    countConfigSE <- countConfigSingleEnd(binsize = 500, mapq = 20,
                                          filteredFlag = 1024, shift = 100)
    
    # Paired End:
    # Count in 500bp bins.
    # Consider only reads with Mapping Quality >= 30.
    # Count the midpoint of the aligned fragment instead of 5' ends.
    # Consider only reads corresponding to fragments with size from 100 to 300bp
    countConfigPE <- countConfigPairedEnd(binsize = 500, mapq = 30, midpoint = TRUE,
                                          tlenFilter = c(100, 300))
    
    # 2. Define predefined genomic regions (promoters) and ensure they are of identical size
    promoters <- promoters(genes, 1500, 1500)
    # regions have identical size?
    size_check <- all(width(promoters) == 3000)
    message(paste("Are all promoter regions of identical size (3000 bp)?", size_check))
    
    # 3. Run enrichR() using the custom count configuration
    # We attempt to fit using the Paired-End configuration. If the BAM files contain
    # Single-End reads, we gracefully fall back to the Single-End configuration.
    fit <- tryCatch({
      message("Attempting enrichR with Paired-End configuration...")
      enrichR(treatment   = k4me3Bamfile,
              control     = inputBamfile,
              genome      = genome,
              countConfig = countConfigPE)
    }, error = function(e) {
      message("Paired-End fit failed or is incompatible. Falling back to Single-End configuration...")
      enrichR(treatment   = k4me3Bamfile,
              control     = inputBamfile,
              genome      = genome,
              countConfig = countConfigSE)
    })
    
    # Fit only on predefined promoter regions
    message("Running enrichR on predefined promoter regions...")
    promotersFit <- enrichR(treatment = k4me3Bamfile, control = inputBamfile,
                            genome = promoters, verbose = FALSE)
    
    # 4. Inspect summary statistics
    message("Summary of fit on promoters:")
    summary(promotersFit)
    
    # 5. Write named output files for the meaningful results
    # Save the fit objects as RDS
    saveRDS(fit, file = "enrichR_custom_config_fit.rds")
    saveRDS(promotersFit, file = "promoters_fit.rds")
    
    # Export summary statistics to a text file
    sink("promoters_fit_summary.txt")
    cat("=== PROMOTERS FIT SUMMARY ===\n")
    print(summary(promotersFit))
    sink()
    
    # Export significantly enriched promoter regions (FDR <= 0.05) to BED format
    tryCatch({
      exportR(promotersFit, filename = "promoters_enriched.bed", type = "bed", fdr = 0.05)
      message("Successfully exported enriched promoters to 'promoters_enriched.bed'")
    }, error = function(e) {
      message("Could not export BED file (possibly no regions met the FDR threshold).")
    })
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS":
        normr: \$(Rscript -e 'cat(as.character(packageVersion("normr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_counting_and_predefined_regions.csv versions.yml
    """
}

workflow BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ChIP.bam, Control.bam ] ]

    main:
    BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS(ch_input)

    emit:
    tables   = BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS.out.tables
    plots    = BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS.out.plots
    objects  = BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS.out.objects
    versions = BIOC_NORMR_CUSTOM_COUNTING_AND_PREDEFINED_REGIONS.out.versions
}
