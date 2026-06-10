#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — differential_enrichment_calling
// Call differential enrichment directly between two ChIP-seq conditions without a control experiment.
// Input: ChIP1.bam, ChIP2.bam
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// R packages: Rsamtools, normr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING {
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
    library(Rsamtools)
    
    # Define input files
    chip1_bam <- "ChIP1.bam"
    chip2_bam <- "ChIP2.bam"
    
    # Verify input files exist
    if (!file.exists(chip1_bam) || !file.exists(chip2_bam)) {
      stop("Required input files 'ChIP1.bam' and/or 'ChIP2.bam' are missing in the working directory.")
    }
    
    # Extract genome information from the BAM header to avoid hardcoding
    bam_header <- Rsamtools::scanBamHeader(chip1_bam)
    targets <- bam_header[[1]]\$targets
    genome <- data.frame(
      seqnames = names(targets),
      length = as.numeric(targets),
      stringsAsFactors = FALSE
    )
    
    # Call differential enrichment directly between the two ChIP-seq conditions
    k4k36Dif <- diffR(treatment = chip1_bam,
                      control   = chip2_bam,
                      genome    = genome,
                      verbose   = FALSE)
    
    # Inspect and save summary statistics
    sink("k4k36Dif_summary.txt")
    summary(k4k36Dif)
    sink()
    
    # Print summary to stdout
    summary(k4k36Dif)
    
    # Export differential regions and normalized differences
    exportR(k4k36Dif, filename = "k4k36Dif.bed", type = "bed", fdr = 0.05)
    exportR(k4k36Dif, filename = "k4k36Dif.bw", type = "bigWig")
    
    # Save the NormRFit object for downstream R analysis
    saveRDS(k4k36Dif, file = "k4k36Dif.rds")
    
    # Export a CSV table of the results
    ranges <- getRanges(k4k36Dif)
    classes <- getClasses(k4k36Dif, fdr = 0.05)
    results_df <- as.data.frame(ranges)
    results_df\$class <- classes
    write.csv(results_df, file = "k4k36Dif_results.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING":
        normr: \$(Rscript -e 'cat(as.character(packageVersion("normr")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_enrichment_calling.csv versions.yml
    """
}

workflow BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ChIP1.bam, ChIP2.bam ] ]

    main:
    BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING(ch_input)

    emit:
    tables   = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING.out.tables
    plots    = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING.out.plots
    objects  = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING.out.objects
    versions = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_CALLING.out.versions
}
