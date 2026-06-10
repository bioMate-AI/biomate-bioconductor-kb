#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — enrichment_regime_stratification
// Identify and classify multiple enrichment regimes (e.g., broad domains vs. sharp peaks) in a ChIP-seq experiment.
// Input: ChIP.bam, Control.bam
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION {
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
    .bm_deps <- c("Rsamtools", "normr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(normr)
    library(Rsamtools)
    
    # Define input files
    chip_bam <- "ChIP.bam"
    control_bam <- "Control.bam"
    
    # Verify input files exist
    if (!file.exists(chip_bam)) {
      stop(paste("Required input file missing:", chip_bam))
    }
    if (!file.exists(control_bam)) {
      stop(paste("Required input file missing:", control_bam))
    }
    
    # Ensure BAM files are indexed
    if (!file.exists(paste0(chip_bam, ".bai")) && !file.exists(sub("\\.bam\$", ".bai", chip_bam))) {
      message("Indexing ChIP.bam...")
      indexBam(chip_bam)
    }
    if (!file.exists(paste0(control_bam, ".bai")) && !file.exists(sub("\\.bam\$", ".bai", control_bam))) {
      message("Indexing Control.bam...")
      indexBam(control_bam)
    }
    
    # Extract genome information (chromosome names and lengths) directly from the BAM header
    message("Extracting genome information from BAM header...")
    bam_header <- scanBamHeader(chip_bam)
    targets <- bam_header[[1]]\$targets
    genome <- data.frame(
      seqnames = names(targets),
      length = as.numeric(targets),
      stringsAsFactors = FALSE
    )
    
    # Fit initial enrichment models to obtain counts and ranges
    message("Fitting initial enrichment models...")
    k4me3Fit <- enrichR(
      treatment = chip_bam,
      control = control_bam,
      genome = genome,
      verbose = FALSE
    )
    
    k36me3Fit <- enrichR(
      treatment = chip_bam,
      control = control_bam,
      genome = genome,
      verbose = FALSE
    )
    
    # === DOCUMENTED CODE ===
    k4me3Regimes <- regimeR(treatment = getCounts(k4me3Fit)\$treatment,
                             control   = getCounts(k4me3Fit)\$control,
                             genome    = getRanges(k4me3Fit),
                             models    = 3,
                             verbose   = FALSE)
    summary(k4me3Regimes)
    
    k36me3Regimes <- regimeR(treatment = getCounts(k36me3Fit)\$treatment,
                             control   = getCounts(k36me3Fit)\$control,
                             genome    = getRanges(k36me3Fit),
                             models    = 3,
                             verbose   = FALSE)
    summary(k36me3Regimes)
    
    exportR(k4me3Regimes, filename = "k4me3Regimes.bed", type = "bed", fdr=0.05)
    exportR(k36me3Regimes, filename = "k36me3Regimes.bed", type = "bed", fdr=0.05)
    # === END DOCUMENTED CODE ===
    
    # Save additional meaningful results
    message("Saving RDS objects and summary statistics...")
    saveRDS(k4me3Regimes, file = "k4me3Regimes.rds")
    saveRDS(k36me3Regimes, file = "k36me3Regimes.rds")
    
    # Write summaries to a text file
    sink("regimes_summary.txt")
    cat("=== H3K4me3 Regimes Summary ===\n")
    print(summary(k4me3Regimes))
    cat("\n=== H3K36me3 Regimes Summary ===\n")
    print(summary(k36me3Regimes))
    sink()
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION":
        normr: \$(Rscript -e 'cat(as.character(packageVersion("normr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichment_regime_stratification.csv versions.yml
    """
}

workflow BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ChIP.bam, Control.bam ] ]

    main:
    BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION(ch_input)

    emit:
    tables   = BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION.out.tables
    plots    = BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION.out.plots
    objects  = BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION.out.objects
    versions = BIOC_NORMR_ENRICHMENT_REGIME_STRATIFICATION.out.versions
}
