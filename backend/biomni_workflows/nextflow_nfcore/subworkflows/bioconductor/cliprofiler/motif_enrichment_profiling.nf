#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cliProfiler — motif_enrichment_profiling
// Analyze and visualize sequence motif enrichment around the center of CLIP-seq peaks using a reference genome.
// Input: peaks.rds
// Container: quay.io/biocontainers/bioconductor-cliprofiler:1.16.0--r45hdfd78af_0
// Requires: BSgenome.Mmusculus.UCSC.mm10, GenomicRanges, cliProfiler, ggplot2
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load peak data
//  * 2. [Core Analysis] Run motifProfile specifying the IUPAC motif, reference BSgenome, and flanking window size

nextflow.enable.dsl = 2

process BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(cliProfiler)
    library(GenomicRanges)
    library(ggplot2)
    
    # Ensure the BSgenome package is loaded/available
    if (!requireNamespace("BSgenome.Mmusculus.UCSC.mm10", quietly = TRUE)) {
        stop("Package 'BSgenome.Mmusculus.UCSC.mm10' is required but not installed.")
    }
    library(BSgenome.Mmusculus.UCSC.mm10)
    
    # 1. Load peak data
    if (!file.exists("peaks.rds")) {
        stop("Input file 'peaks.rds' not found in the working directory.")
    }
    test <- readRDS("peaks.rds")
    
    # 2. Run motifProfile specifying the IUPAC motif, reference BSgenome, and flanking window size
    motif <- motifProfile(test, motif = "DRACH",
        genome = "BSgenome.Mmusculus.UCSC.mm10",
        fraction = TRUE, title = "Motif Profile",
        flanking = 10)
    
    # 3. Write named output files
    # Save the data frame of motif enrichment
    write.csv(motif[[1]], "motif_enrichment_table.csv", row.names = FALSE)
    
    # Save the ggplot object as a PDF
    ggsave("motif_enrichment_plot.pdf", plot = motif[[2]], width = 8, height = 6)
    
    # Save the complete list object as RDS
    saveRDS(motif, "motif_profile_results.rds")

    writeLines(c(
        '"BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING":',
        paste0('    cliProfiler: ', as.character(packageVersion('cliProfiler')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_enrichment_profiling.csv versions.yml
    """
}

workflow BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.rds ] ]

    main:
    BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING(ch_input)

    emit:
    tables   = BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING.out.tables
    plots    = BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING.out.plots
    objects  = BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING.out.objects
    versions = BIOC_CLIPROFILER_MOTIF_ENRICHMENT_PROFILING.out.versions
}
