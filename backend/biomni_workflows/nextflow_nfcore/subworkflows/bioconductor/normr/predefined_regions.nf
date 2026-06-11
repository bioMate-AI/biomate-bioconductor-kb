#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normr — predefined_regions
// Call enrichment on a set of predefined genomic regions (e.g., promoters) of identical size.
// Input: ChIP.bam, Control.bam, genes.bed
// Container: quay.io/biocontainers/bioconductor-normr:1.36.0--r45ha27e39d_0
// R packages: GenomicRanges, normr
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, normr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load gene annotations and define promoter regions of identical size
//  * 2. [Core Analysis] Call enrichment on the predefined promoter regions using enrichR()
//  * 3. [Visualization & Output] Analyze results using summary()

nextflow.enable.dsl = 2

process BIOC_NORMR_PREDEFINED_REGIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GenomicRanges", "normr")
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
    library("normr")
    library("GenomicRanges")
    
    # 1. Load gene annotations and define promoter regions of identical size
    genes <- read.delim(file = "genes.bed",
                        header = FALSE, stringsAsFactors = FALSE)
    
    genes <- GRanges(seqnames = genes[, 1],
                     ranges = IRanges(start = genes[, 2], end = genes[, 3]),
                     strand = genes[, 6],
                     ENSTID = genes[, 4])
    genes <- unique(genes)
    
    promoters <- promoters(genes, 1500, 1500)
    all(width(promoters) == 3000)
    
    # 2. Call enrichment on the predefined promoter regions using enrichR()
    promotersFit <- enrichR(treatment = "ChIP.bam", control = "Control.bam",
                            genome = promoters, verbose = FALSE)
    
    # 3. Analyze and export results
    # Capture and save the summary text
    fit_summary <- capture.output(summary(promotersFit))
    writeLines(fit_summary, con = "promotersFit_summary.txt")
    
    # Save the fitted object as an RDS file
    saveRDS(promotersFit, file = "promotersFit.rds")
    
    # Export coordinates of significantly enriched regions (FDR <= 0.05)
    exportR(promotersFit, filename = "promotersFit_enriched.bed", type = "bed", fdr = 0.05)
    
    # Extract enrichment values and classes to write a comprehensive CSV report
    enrichment_vals <- getEnrichment(promotersFit)
    classes <- getClasses(promotersFit, fdr = 0.05)
    
    results_df <- data.frame(
      seqnames = as.character(seqnames(promoters)),
      start = start(promoters),
      end = end(promoters),
      strand = as.character(strand(promoters)),
      ENSTID = mcols(promoters)\$ENSTID,
      enrichment = enrichment_vals,
      class = classes,
      stringsAsFactors = FALSE
    )
    
    write.csv(results_df, file = "promoters_enrichment_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_NORMR_PREDEFINED_REGIONS":',
        paste0('    normr: ', as.character(packageVersion('normr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predefined_regions.csv versions.yml
    """
}

workflow BIOC_NORMR_PREDEFINED_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ChIP.bam, Control.bam, genes.bed ] ]

    main:
    BIOC_NORMR_PREDEFINED_REGIONS(ch_input)

    emit:
    tables   = BIOC_NORMR_PREDEFINED_REGIONS.out.tables
    plots    = BIOC_NORMR_PREDEFINED_REGIONS.out.plots
    objects  = BIOC_NORMR_PREDEFINED_REGIONS.out.objects
    versions = BIOC_NORMR_PREDEFINED_REGIONS.out.versions
}
