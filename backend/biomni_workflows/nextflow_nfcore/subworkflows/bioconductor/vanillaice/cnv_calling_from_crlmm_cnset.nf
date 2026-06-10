#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VanillaICE — cnv_calling_from_crlmm_cnset
// Coerce a preprocessed CNSet object from the crlmm package to a SnpArrayExperiment, perform wave correction, and fit the HMM.
// Input: cnSetExample
// Container: quay.io/biocontainers/bioconductor-vanillaice:1.72.0--r45h01b2380_0
// R packages: ArrayTV, GenomicRanges, IRanges, VanillaICE, crlmm, oligoClasses
// Bioconductor: 3.20 | R: 4.4
// Requires: ArrayTV, GenomicRanges, IRanges, VanillaICE, crlmm, oligoClasses
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Coerce the CNSet object to a SnpArrayExperiment
//  * 2. [Core Analysis] Perform wave correction using ArrayTV::gcCorrect to correct for GC content bias
//  * 3. [Core Analysis] Fit the 6-state HMM using hmm2

nextflow.enable.dsl = 2

process BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("ArrayTV", "GenomicRanges", "IRanges", "VanillaICE", "crlmm", "oligoClasses")
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
    library(oligoClasses)
    library(VanillaICE)
    library(crlmm)
    library(ArrayTV)
    library(GenomicRanges)
    
    # Read user input
    if (file.exists("cnSetExample")) {
      cnSetExample <- readRDS("cnSetExample")
    } else if (file.exists("cnSetExample.rds")) {
      cnSetExample <- readRDS("cnSetExample.rds")
    } else {
      stop("Required input file 'cnSetExample' or 'cnSetExample.rds' not found in the working directory.")
    }
    
    # Define parameters for gcCorrect
    increms <- c(10, 1000, 100e3)
    wins <- c(100, 10e3, 1e6)
    
    # Execute documented workflow
    se <- as(cnSetExample, "SnpArrayExperiment")
    res <- gcCorrect(lrr(se), increms=increms, maxwins=wins, returnOnlyTV=FALSE, verbose=TRUE, build="hg18", chr=chromosome(se), starts=start(se))
    se2 <- se
    assays(se2)[["cn"]] <- res\$correctedVals
    res <- hmm2(se2)
    
    # Save outputs
    saveRDS(res, "hmm_fit_results.rds")
    
    # Extract segments and save as CSV
    gr <- unlist(res)
    df <- as.data.frame(gr)
    write.csv(df, "cnv_segments.csv", row.names=FALSE)
    
    # Generate a summary plot
    pdf("cnv_summary_plot.pdf")
    if (length(gr) > 0) {
      barplot(table(gr\$state), main="Distribution of HMM States", xlab="State", ylab="Count", col="skyblue")
    } else {
      plot.new()
      text(0.5, 0.5, "No CNVs detected")
    }
    dev.off()

    writeLines(c(
        '"BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET":',
        paste0('    VanillaICE: ', as.character(packageVersion('VanillaICE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_calling_from_crlmm_cnset.csv versions.yml
    """
}

workflow BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cnSetExample ] ]

    main:
    BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET(ch_input)

    emit:
    tables   = BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET.out.tables
    plots    = BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET.out.plots
    objects  = BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET.out.objects
    versions = BIOC_VANILLAICE_CNV_CALLING_FROM_CRLMM_CNSET.out.versions
}
