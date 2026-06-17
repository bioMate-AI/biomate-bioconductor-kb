#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BASiCS — single_group_hvg_lvg_detection
// Quantify technical noise, normalize data, and identify highly and lowly variable genes within a single group of cells.
// Input: counts_matrix.csv, spike_info.csv, batch_info.csv
// Container: quay.io/biocontainers/bioconductor-basics:2.22.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BASiCS, SingleCellExperiment, cowplot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format input data into a SingleCellExperiment object using newBASiCS_Data
//  * 2. [Core Analysis] Run the MCMC sampler using BASiCS_MCMC
//  * 3. [Core Analysis] Detect highly variable genes (HVG) and lowly variable genes (LVG) using BASiCS_DetectHVG and BASiCS_DetectLVG
//  * 4. [Visualization & Output] Visualize variability and extract results using BASiCS_PlotVG and as.data.frame
//  * 5. [Core Analysis] Generate denoised counts or rates using BASiCS_DenoisedCounts or BASiCS_DenoisedRates

nextflow.enable.dsl = 2

process BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION {
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
    .bm_deps <- c("BASiCS", "cowplot")
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
    library(BASiCS)
    library(cowplot)
    
    # 1. Read User Input Files
    if (!file.exists("counts_matrix.csv")) {
      stop("Error: 'counts_matrix.csv' is required but was not found in the working directory.")
    }
    
    Counts <- as.matrix(read.csv("counts_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Check for optional batch info
    BatchInfo <- NULL
    if (file.exists("batch_info.csv")) {
      batch_df <- read.csv("batch_info.csv", stringsAsFactors = FALSE)
      if ("BatchInfo" %in% colnames(batch_df)) {
        BatchInfo <- batch_df\$BatchInfo
      } else {
        BatchInfo <- batch_df[[1]]
      }
    }
    
    # Check for optional spike-in info
    has_spikes <- file.exists("spike_info.csv")
    
    if (has_spikes) {
      SpikeInfo <- read.csv("spike_info.csv", stringsAsFactors = FALSE)
      colnames(SpikeInfo) <- c("SpikeID", "SpikeInput")
      
      # Determine which rows are technical spike-ins
      Tech <- rownames(Counts) %in% SpikeInfo\$SpikeID
      
      # 1a. Data preparation (with spikes)
      if (!is.null(BatchInfo)) {
        DataExample <- newBASiCS_Data(Counts, Tech, SpikeInfo, BatchInfo = BatchInfo)
      } else {
        DataExample <- newBASiCS_Data(Counts, Tech, SpikeInfo)
      }
      
      # 2. Run MCMC sampler (with spikes)
      Chain <- BASiCS_MCMC(
        Data = DataExample,
        N = 1000, Thin = 10, Burn = 500,
        PrintProgress = FALSE, Regression = TRUE
      )
      
      # 3. Detect HVG and LVG
      HVG <- BASiCS_DetectHVG(Chain, VarThreshold = 0.6)
      LVG <- BASiCS_DetectLVG(Chain, VarThreshold = 0.2)
      
      # 4. Plot and extract results
      pdf("hvg_lvg_plots.pdf", width = 10, height = 5)
      print(plot_grid(
        BASiCS_PlotVG(HVG, "Grid"),
        BASiCS_PlotVG(HVG, "VG")
      ))
      dev.off()
      
      hvg_df <- as.data.frame(HVG)
      lvg_df <- as.data.frame(LVG)
      write.csv(hvg_df, "hvg_results.csv", row.names = FALSE)
      write.csv(lvg_df, "lvg_results.csv", row.names = FALSE)
      
      # 5. Obtain denoised counts and rates
      DenoisedCounts <- BASiCS_DenoisedCounts(Data = DataExample, Chain = Chain)
      DenoisedRates <- BASiCS_DenoisedRates(
        Data = DataExample, Chain = Chain,
        Propensities = FALSE
      )
      
    } else {
      # If no spikes, batch info is strictly required
      if (is.null(BatchInfo)) {
        stop("Error: 'batch_info.csv' is required when 'spike_info.csv' is not provided.")
      }
      
      # 1b. Data preparation (without spikes, requires batch info)
      DataExampleNoSpikes <- SingleCellExperiment(
        assays = list(counts = Counts),
        colData = data.frame(BatchInfo = BatchInfo)
      )
      
      # 2. Run MCMC sampler (without spikes)
      Chain <- BASiCS_MCMC(
        Data = DataExampleNoSpikes,
        N = 1000, Thin = 10, Burn = 500,
        WithSpikes = FALSE,
        Regression = TRUE,
        PrintProgress = FALSE
      )
      
      # 3. Detect HVG and LVG
      HVG <- BASiCS_DetectHVG(Chain, VarThreshold = 0.6)
      LVG <- BASiCS_DetectLVG(Chain, VarThreshold = 0.2)
      
      # 4. Plot and extract results
      pdf("hvg_lvg_plots.pdf", width = 10, height = 5)
      print(plot_grid(
        BASiCS_PlotVG(HVG, "Grid"),
        BASiCS_PlotVG(HVG, "VG")
      ))
      dev.off()
      
      hvg_df <- as.data.frame(HVG)
      lvg_df <- as.data.frame(LVG)
      write.csv(hvg_df, "hvg_results.csv", row.names = FALSE)
      write.csv(lvg_df, "lvg_results.csv", row.names = FALSE)
      
      # 5. Obtain denoised counts and rates
      DenoisedCounts <- BASiCS_DenoisedCounts(Data = DataExampleNoSpikes, Chain = Chain)
      DenoisedRates <- BASiCS_DenoisedRates(
        Data = DataExampleNoSpikes, Chain = Chain,
        Propensities = FALSE
      )
    }
    
    # Save final R objects
    saveRDS(Chain, "basics_chain.rds")
    saveRDS(DenoisedCounts, "denoised_counts.rds")
    saveRDS(DenoisedRates, "denoised_rates.rds")

    writeLines(c(
        '"BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION":',
        paste0('    BASiCS: ', as.character(packageVersion('BASiCS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_group_hvg_lvg_detection.csv versions.yml
    """
}

workflow BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts_matrix.csv, spike_info.csv, batch_info.csv ] ]

    main:
    BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION(ch_input)

    emit:
    tables   = BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION.out.tables
    plots    = BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION.out.plots
    objects  = BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION.out.objects
    versions = BIOC_BASICS_SINGLE_GROUP_HVG_LVG_DETECTION.out.versions
}
