#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compEpiTools — read_counting_and_coverage
// Calculate base-level coverage, total coverage, binned coverage, and identify peak summits within genomic regions of interest from aligned BAM files.
// Input: user_regions.RData, aligned_reads.bam
// Container: quay.io/biocontainers/bioconductor-compepitools:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, compEpiTools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate base-level coverage using GRbaseCoverage
//  * 2. [Core Analysis] Calculate total coverage using GRcoverage
//  * 3. [Core Analysis] Calculate binned coverage using GRcoverageInbins
//  * 4. [Core Analysis] Identify peak summits using GRcoverageSummit
//  * 5. [Visualization & Output] Plot coverage and highlight the summit

nextflow.enable.dsl = 2

process BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(compEpiTools)
    library(GenomicRanges)
    
    # Define input file paths
    regions_file <- "user_regions.RData"
    bampath <- "aligned_reads.bam"
    
    # Check if input files exist
    if (!file.exists(regions_file)) {
      stop(paste("Required input file missing:", regions_file))
    }
    if (!file.exists(bampath)) {
      stop(paste("Required input file missing:", bampath))
    }
    
    # Load the GRanges object from user_regions.RData
    env <- new.env()
    load(regions_file, envir = env)
    gr_names <- ls(env)
    gr_objs <- sapply(gr_names, function(x) inherits(env[[x]], "GRanges"))
    
    if (!any(gr_objs)) {
      stop("No GRanges object found in user_regions.RData")
    }
    
    # Extract the first GRanges object found
    gr <- env[[gr_names[which(gr_objs)[1]]]]
    
    # 1. Calculate base-level coverage using GRbaseCoverage
    res <- GRbaseCoverage(Object=gr, bam=bampath)
    
    # 2. Calculate total coverage using GRcoverage
    cov_total <- GRcoverage(Object=gr, bam=bampath, Nnorm=FALSE, Snorm=FALSE)
    
    # 3. Calculate binned coverage using GRcoverageInbins
    cov_bins <- GRcoverageInbins(Object=gr, bam=bampath, Nnorm=FALSE, Snorm=FALSE, Nbins=5)
    
    # 4. Identify peak summits using GRcoverageSummit
    summit <- GRcoverageSummit(Object=gr, bam=bampath)
    
    # Write meaningful results to output files
    saveRDS(res, "base_level_coverage.rds")
    write.csv(as.data.frame(cov_total), "total_coverage.csv", row.names = FALSE)
    write.csv(as.data.frame(cov_bins), "binned_coverage.csv", row.names = FALSE)
    saveRDS(summit, "coverage_summits.rds")
    
    # 5. Plot coverage and highlight the summit
    pdf("coverage_plot.pdf", width=6, height=5)
    plot(res[[1]], type='l', xlab='bp', ylab='reads count')
    abline(v=start(summit[1])-start(gr[1])+1, lty=2, lwd=2)
    dev.off()
    
    # Print summary of results to standard output
    cat("Pipeline completed successfully.\n")
    cat("Total coverage for first region:\n")
    print(cov_total[1])
    cat("Binned coverage for first region:\n")
    print(cov_bins[1,])

    writeLines(c(
        '"BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE":',
        paste0('    compEpiTools: ', as.character(packageVersion('compEpiTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_counting_and_coverage.csv versions.yml
    """
}

workflow BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_regions.RData, aligned_reads.bam ] ]

    main:
    BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE(ch_input)

    emit:
    tables   = BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE.out.tables
    plots    = BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE.out.plots
    objects  = BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE.out.objects
    versions = BIOC_COMPEPITOOLS_READ_COUNTING_AND_COVERAGE.out.versions
}
