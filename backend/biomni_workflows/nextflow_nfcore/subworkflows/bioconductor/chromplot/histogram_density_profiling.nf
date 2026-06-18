#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chromPlot — histogram_density_profiling
// Plot single or stacked density histograms of genomic features (such as transcripts or differentially expressed genes) on the sides of chromosomes.
// Input: hg_gap, txgr, refGeneHg, ref_mm10, array, DEneg, DEpos, monocytes
// Container: quay.io/biocontainers/bioconductor-chromplot:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, chromPlot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load coordinate gaps and cytobands
//  * 2. [Input & Preparation] Extract or load genomic features
//  * 3. [Visualization & Output] Plot single track density histograms
//  * 4. [Visualization & Output] Plot stacked histograms representing multiple filtering stages (e.g., reference genes vs. array genes vs. differentially expressed
//  * 5. [Visualization & Output] Plot stacked histograms categorized by a single grouping variable

nextflow.enable.dsl = 2

process BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("chromPlot", "GenomicRanges")
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
        library(chromPlot)
        library(GenomicRanges)
        
        # Helper function to robustly read user input files from the working directory
        # Supports RDS, tab-separated TXT, and CSV formats.
        read_input <- function(name, is_granges = FALSE) {
          rds_path <- paste0(name, ".rds")
          txt_path <- paste0(name, ".txt")
          csv_path <- paste0(name, ".csv")
          
          if (file.exists(rds_path)) {
            return(readRDS(rds_path))
          } else if (file.exists(txt_path)) {
            df <- read.table(txt_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
            if (is_granges) {
              return(makeGRangesFromDataFrame(df, keep.extra.columns = TRUE))
            }
            return(df)
          } else if (file.exists(csv_path)) {
            df <- read.csv(csv_path, header = TRUE, stringsAsFactors = FALSE)
            if (is_granges) {
              return(makeGRangesFromDataFrame(df, keep.extra.columns = TRUE))
            }
            return(df)
          } else {
            stop(paste("Required input file not found in working directory:", name))
          }
        }
        
        # 1. Load coordinate gaps, cytobands, and genomic features from user input
        hg_gap <- read_input("hg_gap")
        txgr <- read_input("txgr", is_granges = TRUE)
        refGeneHg <- read_input("refGeneHg")
        ref_mm10 <- read_input("ref_mm10")
        array <- read_input("array")
        DEneg <- read_input("DEneg")
        DEpos <- read_input("DEpos")
        monocytes <- read_input("monocytes")
        
        # Load additional required coordinate/band files from package data
        hg_cytoBandIdeo <- chromPlot::hg_cytoBandIdeo
        mm10_gap <- chromPlot::mm10_gap
        mm10_cytoBandIdeo <- chromPlot::mm10_cytoBandIdeo
        
        # Write a summary table of the loaded inputs
        summary_df <- data.frame(
          Dataset = c("hg_gap", "txgr", "refGeneHg", "ref_mm10", "array", "DEneg", "DEpos", "monocytes"),
          Type = c("data.frame", "GRanges", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame", "data.frame"),
          Elements = c(
            nrow(hg_gap), 
            length(txgr), 
            nrow(refGeneHg), 
            nrow(ref_mm10), 
            nrow(array), 
            nrow(DEneg), 
            nrow(DEpos), 
            nrow(monocytes)
          )
        )
        write.csv(summary_df, "workflow_input_summary.csv", row.names = FALSE)
        
        # 2. Plot single track density histograms
        pdf("plot1_single_histogram.pdf", width = 10, height = 8)
        chromPlot(gaps=hg_gap, annot1=txgr)
        dev.off()
        
        # 3. Plot single track density histograms with cytobands
        pdf("plot2_refGene_histogram.pdf", width = 10, height = 8)
        chromPlot(gaps=hg_gap, bands=hg_cytoBandIdeo, annot1=refGeneHg, chr=c(19:21), figCols=3)
        dev.off()
        
        # 4. Plot stacked histograms representing multiple filtering stages
        pdf("plot3_stacked_histograms.pdf", width = 10, height = 8)
        chromPlot(gaps=mm10_gap, bands=mm10_cytoBandIdeo, annot1=ref_mm10, annot2=array, annot3=DEneg, annot4=DEpos, chr=c( "17", "18", "19"), figCols=3, chrSide=c(-1, -1, -1, 1, -1, 1, -1, 1), noHist=FALSE)
        dev.off()
        
        # 5. Plot stacked histograms categorized by a single grouping variable
        pdf("plot4_monocytes_segments.pdf", width = 10, height = 8)
        chromPlot(gaps=hg_gap, bands=hg_cytoBandIdeo, annot1=refGeneHg, segment=monocytes, chrSide=c(-1,1,1,1,1,1,1,1), figCols=3, chr=c(19:21))
        dev.off()
        
        # Save the final workspace state for reproducibility
        saveRDS(summary_df, "workflow_output_summary.rds")

    writeLines(c(
        '"BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING":',
        paste0('    chromPlot: ', as.character(packageVersion('chromPlot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_histogram_density_profiling.csv versions.yml
    """
}

workflow BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg_gap, txgr, refGeneHg, ref_mm10, array, DEneg, DEpos, monocytes ] ]

    main:
    BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING(ch_input)

    emit:
    tables   = BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING.out.tables
    plots    = BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING.out.plots
    objects  = BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING.out.objects
    versions = BIOC_CHROMPLOT_HISTOGRAM_DENSITY_PROFILING.out.versions
}
