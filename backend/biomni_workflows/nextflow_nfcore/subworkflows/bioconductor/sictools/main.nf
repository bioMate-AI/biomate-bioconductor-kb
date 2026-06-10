#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sictools — snp_diff_detection
// Detect single nucleotide variant (SNV) differences between two closely related BAM files across a genomic region of interest.
// Input: bam1.bam, bam2.bam, ref.fasta
// Container: quay.io/biocontainers/bioconductor-sictools:1.30.0--r43h54b6a8d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SICTOOLS_SNP_DIFF_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-sictools:1.30.0--r43h54b6a8d_0"

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
    .bm_deps <- c("Rsamtools", "sictools")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(SICtools)
    library(Rsamtools)
    
    # Define input file paths from the working directory
    bam1 <- "bam1.bam"
    bam2 <- "bam2.bam"
    refFsa <- "ref.fasta"
    
    # Verify that input files exist
    if (!file.exists(bam1)) {
      stop(paste("Required input file missing:", bam1))
    }
    if (!file.exists(bam2)) {
      stop(paste("Required input file missing:", bam2))
    }
    if (!file.exists(refFsa)) {
      stop(paste("Required input file missing:", refFsa))
    }
    
    # Ensure BAM files are indexed (required for pileup/applyPileups)
    if (!file.exists(paste0(bam1, ".bai")) && !file.exists(gsub("\\.bam\$", ".bai", bam1))) {
      message("Indexing bam1.bam...")
      tryCatch(indexBam(bam1), error = function(e) warning("Failed to index bam1.bam: ", e\$message))
    }
    if (!file.exists(paste0(bam2, ".bai")) && !file.exists(gsub("\\.bam\$", ".bai", bam2))) {
      message("Indexing bam2.bam...")
      tryCatch(indexBam(bam2), error = function(e) warning("Failed to index bam2.bam: ", e\$message))
    }
    
    # Ensure Reference FASTA is indexed
    if (!file.exists(paste0(refFsa, ".fai"))) {
      message("Indexing ref.fasta...")
      tryCatch(indexFa(refFsa), error = function(e) warning("Failed to index ref.fasta: ", e\$message))
    }
    
    # Dynamically determine a valid genomic region from the BAM header to ensure runnability
    hdr <- scanBamHeader(bam1)
    targets <- hdr[[1]]\$targets
    
    if (length(targets) == 0) {
      stop("No chromosomes/targets found in the BAM header of bam1.bam")
    }
    
    regChr <- names(targets)[1]
    
    # Find a region with reads to avoid empty outputs, or default to the first 50kb
    param <- ScanBamParam(what = c("pos", "qwidth"), seqnames = regChr)
    bam_reads <- scanBam(bam1, param = param)[[1]]
    valid_pos <- bam_reads\$pos[!is.na(bam_reads\$pos)]
    
    if (length(valid_pos) > 0) {
      regStart <- min(valid_pos)
      regEnd <- max(valid_pos + bam_reads\$qwidth[!is.na(bam_reads\$pos)] - 1)
      # Limit region size to prevent excessive runtimes
      if ((regEnd - regStart) > 100000) {
        regEnd <- regStart + 100000
      }
    } else {
      regStart <- 1
      regEnd <- min(50000, as.numeric(targets[1]))
    }
    
    message(sprintf("Running snpDiff on region %s:%d-%d", regChr, regStart, regEnd))
    
    # Run snpDiff to calculate p-values and d-values for SNVs in the target region
    snpDiffDf <- snpDiff(bam1, bam2, refFsa, regChr, regStart, regEnd, pValueCutOff=1, baseDistCutOff=0)
    
    # Sort the resulting data frame by p-value and d-value to identify candidate variants
    if (!is.null(snpDiffDf) && nrow(snpDiffDf) > 0) {
      snpDiffDfSort <- snpDiffDf[order(snpDiffDf\$p.value, snpDiffDf\$d.value), ]
    } else {
      message("No SNV differences detected in the specified region.")
      snpDiffDfSort <- data.frame()
    }
    
    # Write outputs
    write.csv(snpDiffDfSort, "snp_diff_results.csv", row.names = FALSE)
    saveRDS(snpDiffDfSort, "snp_diff_results.rds")
    
    # Generate diagnostic plot
    pdf("snp_diff_plot.pdf")
    if (!is.null(snpDiffDf) && nrow(snpDiffDf) > 0) {
      plot(-log10(snpDiffDf\$p.value), snpDiffDf\$d.value, col='brown',
           xlab="-log10(p-value)", ylab="d-value", 
           main=paste("SNV Differences in", regChr))
    } else {
      plot(1, type="n", axes=FALSE, xlab="", ylab="")
      text(1, 1, "No SNV differences detected to plot.")
    }
    dev.off()
    
    message("Workflow completed successfully. Outputs written to 'snp_diff_results.csv', 'snp_diff_results.rds', and 'snp_diff_plot.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SICTOOLS_SNP_DIFF_DETECTION":
        sictools: \$(Rscript -e 'cat(as.character(packageVersion("sictools")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_diff_detection.csv versions.yml
    """
}

workflow BIOC_SICTOOLS_SNP_DIFF_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam1.bam, bam2.bam, ref.fasta ] ]

    main:
    BIOC_SICTOOLS_SNP_DIFF_DETECTION(ch_input)

    emit:
    tables   = BIOC_SICTOOLS_SNP_DIFF_DETECTION.out.tables
    plots    = BIOC_SICTOOLS_SNP_DIFF_DETECTION.out.plots
    objects  = BIOC_SICTOOLS_SNP_DIFF_DETECTION.out.objects
    versions = BIOC_SICTOOLS_SNP_DIFF_DETECTION.out.versions
}
