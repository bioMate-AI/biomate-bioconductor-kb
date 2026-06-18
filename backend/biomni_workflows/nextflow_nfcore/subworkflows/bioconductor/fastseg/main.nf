#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fastseg — genomic_ranges_segmentation
// Segment genomic data represented as a GRanges object to identify copy number segments and plot the results.
// Input: gr
// Container: quay.io/biocontainers/bioconductor-fastseg:1.56.0--r45ha27e39d_0
// R packages: DNAcopy, fastseg, GenomicRanges, oligo
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, fastseg
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load GenomicRanges and fastseg packages
//  * 2. [Core Analysis] Run segmentation using fastseg
//  * 3. [Visualization & Output] Plot the segmentation results using segPlot

nextflow.enable.dsl = 2

process BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("DNAcopy", "fastseg", "GenomicRanges", "oligo")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(fastseg)
    library(GenomicRanges)
    
    # Read the user input GRanges object from the working directory
    if (file.exists("gr")) {
      gr_input <- readRDS("gr")
    } else if (file.exists("gr.rds")) {
      gr_input <- readRDS("gr.rds")
    } else {
      stop("Error: Input file 'gr' or 'gr.rds' not found in the working directory.")
    }
    
    # Extract necessary components from the input GRanges object to match the documented workflow
    chrom <- as.character(seqnames(gr_input))
    maploc <- start(gr_input)
    data <- as.matrix(mcols(gr_input))
    samplenames <- colnames(mcols(gr_input))
    
    ## with both individuals
    gr <- GRanges(seqnames=chrom,
            ranges=IRanges(maploc, end=maploc))
    mcols(gr) <- data
    colnames(mcols(gr)) <- samplenames
    res <- fastseg(gr)
    head(res)
    
    # Save results for both individuals
    write.csv(as.data.frame(res), "res_both.csv", row.names=FALSE)
    saveRDS(res, "res_both.rds")
    
    ## with one individual
    gr2 <- gr
    data2 <- as.matrix(data[, 1])
    colnames(data2) <- "sample1"
    mcols(gr2) <- data2
    res_one <- fastseg(gr2)
    head(res_one)
    
    # Save results for one individual
    write.csv(as.data.frame(res_one), "res_one.csv", row.names=FALSE)
    saveRDS(res_one, "res_one.rds")
    
    ## with both individuals and custom threshold
    gr <- GRanges(seqnames=chrom,
            ranges=IRanges(maploc, end=maploc))
    mcols(gr) <- data
    colnames(mcols(gr)) <- samplenames
    res <- fastseg(gr,segMedianT=0.2)
    
    # Save results with custom threshold
    write.csv(as.data.frame(res), "res_both_segMedianT.csv", row.names=FALSE)
    saveRDS(res, "res_both_segMedianT.rds")
    
    # Plotting the segmentation results
    pdf("segplot_whole_genome.pdf", width=10, height=8)
    segPlot(gr, res, plot.type="w")
    dev.off()
    
    pdf("segplot_single_chrom.pdf", width=10, height=10)
    segPlot(gr, res, plot.type="s")
    dev.off()

    writeLines(c(
        '"BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION":',
        paste0('    fastseg: ', as.character(packageVersion('fastseg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_ranges_segmentation.csv versions.yml
    """
}

workflow BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gr ] ]

    main:
    BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION(ch_input)

    emit:
    tables   = BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION.out.tables
    plots    = BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION.out.plots
    objects  = BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION.out.objects
    versions = BIOC_FASTSEG_GENOMIC_RANGES_SEGMENTATION.out.versions
}
