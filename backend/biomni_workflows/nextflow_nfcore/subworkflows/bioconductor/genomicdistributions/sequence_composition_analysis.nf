#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenomicDistributions — sequence_composition_analysis
// Calculate and visualize GC content and dinucleotide frequencies within query genomic ranges.
// Input: queryFile.bed
// Container: quay.io/biocontainers/bioconductor-genomicdistributions:1.18.0--r45hdfd78af_0
// R packages: GenomicDistributions, GenomicRanges, ggplot2, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, GenomicDistributions, GenomicRanges, ggplot2, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import query genomic ranges
//  * 2. [Core Analysis] Calculate GC content using calcGCContentRef
//  * 3. [Visualization & Output] Plot GC content distribution using plotGCContent
//  * 4. [Core Analysis] Calculate dinucleotide frequencies using calcDinuclFreqRef
//  * 5. [Visualization & Output] Plot dinucleotide frequencies using plotDinuclFreq

nextflow.enable.dsl = 2

process BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS {
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
    .bm_deps <- c("GenomicDistributions", "GenomicRanges", "ggplot2", "rtracklayer")
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
    library("GenomicDistributions")
    library("rtracklayer")
    library("GenomicRanges")
    library("ggplot2")
    
    # Ensure the required BSgenome package is available
    if (!requireNamespace("BSgenome.Hsapiens.UCSC.hg19", quietly = TRUE)) {
      stop("The 'BSgenome.Hsapiens.UCSC.hg19' package is required for hg19 sequence composition analysis. Please install it.")
    }
    
    # 1. Import query genomic ranges from the user input file
    queryFile = "queryFile.bed"
    if (!file.exists(queryFile)) {
      stop(paste("Required input file", queryFile, "not found in the working directory."))
    }
    
    query = rtracklayer::import(queryFile)
    
    # 2. Calculate GC content using calcGCContentRef
    message("Calculating GC content for single query...")
    gc1 = calcGCContentRef(query, "hg19")
    write.csv(as.data.frame(gc1), "gc_content_single.csv", row.names = FALSE)
    
    # 3. Plot GC content distribution using plotGCContent
    message("Plotting GC content...")
    p_gc1 = plotGCContent(gc1)
    ggsave("gc_content_single_plot.pdf", plot = p_gc1, width = 7, height = 5)
    
    # 4. Calculate dinucleotide frequencies using calcDinuclFreqRef
    message("Calculating dinucleotide frequencies for single query...")
    df1 = calcDinuclFreqRef(query, "hg19")
    write.csv(as.data.frame(df1), "dinucl_freq_single.csv", row.names = FALSE)
    
    message("Calculating raw dinucleotide counts for single query...")
    df3 = calcDinuclFreqRef(query, "hg19", rawCounts=TRUE)
    write.csv(as.data.frame(df3), "dinucl_raw_counts_single.csv", row.names = FALSE)
    
    # 5. Plot dinucleotide frequencies using plotDinuclFreq
    message("Plotting dinucleotide frequencies...")
    p_df1 = plotDinuclFreq(df1)
    ggsave("dinucl_freq_single_plot.pdf", plot = p_df1, width = 8, height = 6)
    
    p_df3 = plotDinuclFreq(df3)
    ggsave("dinucl_raw_counts_single_plot.pdf", plot = p_df3, width = 8, height = 6)
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS":',
        paste0('    GenomicDistributions: ', as.character(packageVersion('GenomicDistributions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_composition_analysis.csv versions.yml
    """
}

workflow BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ queryFile.bed ] ]

    main:
    BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS.out.tables
    plots    = BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS.out.plots
    objects  = BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS.out.objects
    versions = BIOC_GENOMICDISTRIBUTIONS_SEQUENCE_COMPOSITION_ANALYSIS.out.versions
}
