#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — differential_enrichment
// Call differential enrichment directly between two ChIP-seq conditions without a control experiment.
// Input: ChIP1.bam, ChIP2.bam
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// R packages: GenomicRanges, Rsamtools, normr
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Rsamtools, normr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Call differential enrichment using diffR()
//  * 2. [Visualization & Output] Analyze results using summary()
//  * 3. [Visualization & Output] Export differential regions and normalized differences using exportR()

nextflow.enable.dsl = 2

process BIOC_NORMR_DIFFERENTIAL_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    library(Rsamtools)
    library(GenomicRanges)
    
    # Define input files
    chip1_bam <- "ChIP1.bam"
    chip2_bam <- "ChIP2.bam"
    
    # Check if input files exist
    if (!file.exists(chip1_bam) || !file.exists(chip2_bam)) {
      stop("Required input files 'ChIP1.bam' and/or 'ChIP2.bam' are missing in the working directory.")
    }
    
    # Extract genome information from BAM header to avoid hardcoding hg19
    bam_header <- scanBamHeader(chip1_bam)[[1]]\$targets
    genome <- data.frame(
      seqnames = names(bam_header),
      length = as.numeric(bam_header),
      stringsAsFactors = FALSE
    )
    
    # --- DOCUMENTED CODE ---
    k4k36Dif <- diffR(treatment = chip1_bam,
                      control   = chip2_bam,
                      genome    = genome,
                      verbose   = FALSE)
    
    summary(k4k36Dif)
    
    exportR(k4k36Dif, filename = "k4k36Dif.bed", type = "bed", fdr = 0.05)
    exportR(k4k36Dif, filename = "k4k36Dif.bw", type = "bigWig")
    # --- END DOCUMENTED CODE ---
    
    # Save RDS object
    saveRDS(k4k36Dif, file = "k4k36Dif.rds")
    
    # Save summary output to text file
    sink("k4k36Dif_summary.txt")
    summary(k4k36Dif)
    sink()
    
    # Export CSV table of results
    tryCatch({
      ranges <- getRanges(k4k36Dif)
      ranges\$class <- getClasses(k4k36Dif, fdr = 0.05)
      ranges\$enrichment <- getEnrichment(k4k36Dif)
      write.csv(as.data.frame(ranges), file = "k4k36Dif_results.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not export CSV table: ", e\$message)
    })
    
    # Export PDF plot
    tryCatch({
      pdf("k4k36Dif_plots.pdf")
      enr <- getEnrichment(k4k36Dif)
      hist(enr, breaks = 50, col = "skyblue",
           main = "Normalized Difference Distribution",
           xlab = "Enrichment (log2 fold change)")
      dev.off()
    }, error = function(e) {
      warning("Could not export PDF plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_NORMR_DIFFERENTIAL_ENRICHMENT":',
        paste0('    normr: ', as.character(packageVersion('normr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_enrichment.csv versions.yml
    """
}

workflow BIOC_NORMR_DIFFERENTIAL_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ChIP1.bam, ChIP2.bam ] ]

    main:
    BIOC_NORMR_DIFFERENTIAL_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT.out.tables
    plots    = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT.out.plots
    objects  = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT.out.objects
    versions = BIOC_NORMR_DIFFERENTIAL_ENRICHMENT.out.versions
}
