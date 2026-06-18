#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GenVisR — copy_number_profiling
// Visualize copy number segments at the cohort level or raw copy number calls for a single sample.
// Input: LucCNseg, data
// Container: quay.io/biocontainers/bioconductor-genvisr:1.42.2--r45hdfd78af_0
// R packages: GenVisR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenVisR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Plot cohort-level copy number segments using cnSpec
//  * 2. [Visualization & Output] Plot single-sample raw copy number calls with an ideogram track using cnView
//  * 3. [Visualization & Output] Overlay segment calls on the single-sample plot

nextflow.enable.dsl = 2

process BIOC_GENVISR_COPY_NUMBER_PROFILING {
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
    .bm_deps <- c("GenVisR")
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
        library(GenVisR)
        
        # Function to safely read input files with or without common extensions
        read_input <- function(filename) {
          if (file.exists(filename)) {
            return(read.csv(filename, stringsAsFactors = FALSE))
          } else if (file.exists(paste0(filename, ".csv"))) {
            return(read.csv(paste0(filename, ".csv"), stringsAsFactors = FALSE))
          } else if (file.exists(paste0(filename, ".tsv"))) {
            return(read.delim(paste0(filename, ".tsv"), stringsAsFactors = FALSE))
          } else if (file.exists(paste0(filename, ".txt"))) {
            return(read.delim(paste0(filename, ".txt"), stringsAsFactors = FALSE))
          } else {
            stop(paste("Required input file", filename, "not found in the working directory."))
          }
        }
        
        # Load user inputs
        LucCNseg <- read_input("LucCNseg")
        data <- read_input("data")
        
        # Ensure correct data types and column structures for GenVisR functions
        LucCNseg\$chromosome <- as.character(LucCNseg\$chromosome)
        LucCNseg\$start <- as.numeric(LucCNseg\$start)
        LucCNseg\$end <- as.numeric(LucCNseg\$end)
        LucCNseg\$segmean <- as.numeric(LucCNseg\$segmean)
        if ("sample" %in% colnames(LucCNseg)) {
          LucCNseg\$sample <- as.character(LucCNseg\$sample)
        }
        
        data\$chromosome <- as.character(data\$chromosome)
        data\$coordinate <- as.numeric(data\$coordinate)
        data\$cn <- as.numeric(data\$cn)
        
        # Extract chromosome dynamically from data
        plot_chr <- as.character(unique(data\$chromosome)[1])
        
        # Define dataSeg from the input LucCNseg to overlay segment calls
        # Filter for a single sample to prevent overlapping segments from multiple samples
        dataSeg <- as.data.frame(LucCNseg)
        if ("sample" %in% colnames(dataSeg)) {
          if ("sample" %in% colnames(data)) {
            dataSeg <- dataSeg[dataSeg\$sample == data\$sample[1], ]
          } else {
            dataSeg <- dataSeg[dataSeg\$sample == dataSeg\$sample[1], ]
          }
        }
        
        # Stage 1: Plot cohort-level copy number segments using cnSpec
        pdf("cohort_cn_segments_cnSpec.pdf", width = 10, height = 6)
        cnSpec(LucCNseg, genome = "hg19")
        dev.off()
        
        # Stage 2: Plot single-sample raw copy number calls with an ideogram track using cnView
        pdf("single_sample_raw_cnView.pdf", width = 10, height = 6)
        cnView(data, chr = plot_chr, genome = "hg19", ideogram_txtSize = 4)
        dev.off()
        
        # Stage 3: Overlay segment calls on the single-sample plot
        pdf("single_sample_overlay_cnView.pdf", width = 10, height = 6)
        cnView(data, z = dataSeg, chr = plot_chr, genome = "hg19", ideogram_txtSize = 4)
        dev.off()
        
        # Save processed data objects as RDS for downstream analysis or reproducibility
        saveRDS(LucCNseg, "processed_LucCNseg.rds")
        saveRDS(data, "processed_data.rds")
        saveRDS(dataSeg, "processed_dataSeg.rds")

    writeLines(c(
        '"BIOC_GENVISR_COPY_NUMBER_PROFILING":',
        paste0('    GenVisR: ', as.character(packageVersion('GenVisR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_copy_number_profiling.csv versions.yml
    """
}

workflow BIOC_GENVISR_COPY_NUMBER_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ LucCNseg, data ] ]

    main:
    BIOC_GENVISR_COPY_NUMBER_PROFILING(ch_input)

    emit:
    tables   = BIOC_GENVISR_COPY_NUMBER_PROFILING.out.tables
    plots    = BIOC_GENVISR_COPY_NUMBER_PROFILING.out.plots
    objects  = BIOC_GENVISR_COPY_NUMBER_PROFILING.out.objects
    versions = BIOC_GENVISR_COPY_NUMBER_PROFILING.out.versions
}
