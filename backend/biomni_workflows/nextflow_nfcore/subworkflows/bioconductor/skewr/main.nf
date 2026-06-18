#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: skewr — illumina_450k_qc_and_visualization
// Load raw Illumina 450k IDAT files, preprocess/normalize them, fit skew-normal mixture models to the intensity distributions, and generate diagnostic panel plots
// Input: baseDir, melon.raw
// Container: quay.io/biocontainers/bioconductor-skewr:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: skewr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve barcodes from IDAT directory using getBarcodes
//  * 2. [Input & Preparation] Load raw data into a MethyLumiSet using getMethyLumiSet
//  * 3. [Core Analysis] Preprocess/normalize the data using preprocess
//  * 4. [Core Analysis] Estimate skew-normal mixture model parameters for methylated and unmethylated probes across Type I-red, Type I-green, and Type II 
//  * 5. [Core Analysis] Group the mixture models into lists (methylated first, then unmethylated)
//  * 6. [Visualization & Output] Generate diagnostic panel plots or individual frame plots using panelPlots

nextflow.enable.dsl = 2

process BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("skewr")
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
    library(skewr)
    
    # Define input paths
    baseDir <- "baseDir"
    melon_raw_path <- "melon.raw"
    melon_raw_rds_path <- "melon.raw.rds"
    
    # Validate and read user inputs
    if (!dir.exists(baseDir)) {
      stop(paste("Error: baseDir directory does not exist at:", baseDir))
    }
    
    if (file.exists(melon_raw_path)) {
      melon.raw <- readRDS(melon_raw_path)
    } else if (file.exists(melon_raw_rds_path)) {
      melon.raw <- readRDS(melon_raw_rds_path)
    } else {
      stop("Error: melon.raw or melon.raw.rds file not found in the working directory.")
    }
    
    # 1. Retrieve barcodes from IDAT directory
    barcodes <- getBarcodes(path = baseDir)
    if (length(barcodes) == 0) {
      stop("Error: No barcodes found in the specified baseDir.")
    }
    
    # 2. Load raw data into a MethyLumiSet
    # Process up to the first 2 barcodes as in the documented workflow
    num_barcodes_to_use <- min(2, length(barcodes))
    methylumiset.raw <- getMethyLumiSet(path = baseDir, barcodes = barcodes[1:num_barcodes_to_use])
    
    # 3. Preprocess/normalize the data
    methylumiset.illumina <- preprocess(methylumiset.raw, norm = 'illumina', bg.corr = FALSE)
    
    # Save the preprocessed MethyLumiSet object
    saveRDS(methylumiset.illumina, file = "methylumiset_illumina.rds")
    
    # 4. Estimate skew-normal mixture model parameters
    sn.raw.meth.I.red <- getSNparams(melon.raw, 'M', 'I-red')
    sn.raw.unmeth.I.red <- getSNparams(melon.raw, 'U', 'I-red')
    sn.raw.meth.I.green <- getSNparams(melon.raw, 'M', 'I-green')
    sn.raw.unmeth.I.green <- getSNparams(melon.raw, 'U', 'I-green')
    sn.raw.meth.II <- getSNparams(melon.raw, 'M', 'II')
    sn.raw.unmeth.II <- getSNparams(melon.raw, 'U', 'II')
    
    # 5. Group the mixture models into lists (methylated first, then unmethylated)
    raw.I.red.mixes <- list(sn.raw.meth.I.red, sn.raw.unmeth.I.red)
    raw.I.green.mixes <- list(sn.raw.meth.I.green, sn.raw.unmeth.I.green)
    raw.II.mixes <- list(sn.raw.meth.II, sn.raw.unmeth.II)
    
    # Save the estimated mixture models
    saveRDS(raw.I.red.mixes, file = "raw_I_red_mixes.rds")
    saveRDS(raw.I.green.mixes, file = "raw_I_green_mixes.rds")
    saveRDS(raw.II.mixes, file = "raw_II_mixes.rds")
    
    # 6. Generate diagnostic panel plots and individual frame plots
    pdf("panel_plots_raw.pdf", width = 10, height = 10)
    panelPlots(melon.raw, raw.I.red.mixes, raw.I.green.mixes,
               raw.II.mixes, norm = 'Raw')
    dev.off()
    
    pdf("frame_plots_raw.pdf", width = 10, height = 10)
    panelPlots(melon.raw, raw.I.red.mixes, raw.I.green.mixes,
               raw.II.mixes, plot='frames', frame.nums=c(1,3), norm='Raw')
    dev.off()

    writeLines(c(
        '"BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION":',
        paste0('    skewr: ', as.character(packageVersion('skewr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_illumina_450k_qc_and_visualization.csv versions.yml
    """
}

workflow BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ baseDir, melon.raw ] ]

    main:
    BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION.out.tables
    plots    = BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION.out.plots
    objects  = BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION.out.objects
    versions = BIOC_SKEWR_ILLUMINA_450K_QC_AND_VISUALIZATION.out.versions
}
