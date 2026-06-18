#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosaics — two_sample_genomic_features
// Identify peaks in low-depth ChIP-seq data by incorporating mappability, GC content, and sequence ambiguity.
// Input: chip_chr21.txt, input_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt
// Container: quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0
// R packages: mosaics
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: mosaic plot

nextflow.enable.dsl = 2

process BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0"

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
    .bm_deps <- c("mosaics")
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
    
    # Load the required Bioconductor package
    library(mosaics)
    
    # Define the exact user input files in the working directory
    chip_file  <- "chip_chr21.txt"
    input_file <- "input_chr21.txt"
    m_file     <- "M_chr21.txt"
    gc_file    <- "GC_chr21.txt"
    n_file     <- "N_chr21.txt"
    
    # Verify that all required input files exist in the working directory
    required_files <- c(chip_file, input_file, m_file, gc_file, n_file)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input files in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # --- Read bin-level data with genomic features ---
    # (Replaces the system.file/mosaicsExample setup with local user files)
    exampleBinData <- readBins( 
      type=c("chip","input","M","GC","N"),
      fileName=c(chip_file, input_file, m_file, gc_file, n_file)
    )
    
    # Save the imported bin data object for reproducibility
    saveRDS(exampleBinData, file = "mosaics_bin_data.rds")
    
    # Generate exploratory plots and save them to a PDF
    pdf("mosaics_exploratory_plots.pdf", width = 8, height = 6)
    tryCatch({
      plot( exampleBinData, plotType="M" )
      plot( exampleBinData, plotType="GC" )
      plot( exampleBinData, plotType="M|input" )
      plot( exampleBinData, plotType="GC|input" )
    }, error = function(e) {
      warning("Could not generate all exploratory plots: ", e\$message)
    })
    dev.off()
    
    # --- Fit MOSAiCS model with TS (Two-Sample with genomic ---
    exampleFit <- mosaicsFit( exampleBinData, analysisType="TS", bgEst="automatic" )
    
    # Save the fitted model object
    saveRDS(exampleFit, file = "mosaics_fit.rds")
    
    # Generate and save Goodness of Fit (GOF) plot
    pdf("mosaics_gof_plot.pdf", width = 8, height = 6)
    tryCatch({
      plot(exampleFit)
    }, error = function(e) {
      warning("Could not generate Goodness of Fit plot: ", e\$message)
    })
    dev.off()
    
    # --- Call peaks using the fitted model ---
    OneSamplePeak <- mosaicsPeak( 
      exampleFit, 
      signalModel="2S", 
      FDR=0.05,
      maxgap=200, 
      minsize=50, 
      thres=10 
    )
    
    # Save the peak calling object
    saveRDS(OneSamplePeak, file = "mosaics_peaks.rds")
    
    # Export the peak calling results to standard formats
    export( OneSamplePeak, type="txt", filename="OneSamplePeak.txt" )
    export( OneSamplePeak, type="bed", filename="OneSamplePeak.bed" )
    export( OneSamplePeak, type="gff", filename="OneSamplePeak.gff" )
    
    # Print summary of identified peaks to the console
    print(OneSamplePeak)

    writeLines(c(
        '"BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES":',
        paste0('        mosaics: ', as.character(packageVersion("mosaics")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_sample_genomic_features.csv versions.yml
    """
}

workflow BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_chr21.txt, input_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt ] ]

    main:
    BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES(ch_input)

    emit:
    tables   = BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES.out.tables
    plots    = BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES.out.plots
    objects  = BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES.out.objects
    versions = BIOC_MOSAICS_TWO_SAMPLE_GENOMIC_FEATURES.out.versions
}
