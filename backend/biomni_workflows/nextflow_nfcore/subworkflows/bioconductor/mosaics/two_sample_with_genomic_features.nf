#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosaics — two_sample_with_genomic_features
// Identify peaks in low-depth ChIP-seq data using matched control and genomic features (mappability, GC content, sequence ambiguity).
// Input: chip_chr21.txt, input_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt
// Container: quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0
// R packages: mosaics
// Bioconductor: 3.20 | R: 4.4
// Requires: mosaics
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read bin-level data with genomic features
//  * 2. [Core Analysis] Fit MOSAiCS model with TS analysis
//  * 3. [Core Analysis] Call peaks

nextflow.enable.dsl = 2

process BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("mosaics")
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
    
    # Load the required Bioconductor package
    library(mosaics)
    
    # Define the local input files as specified by the user
    chip_file  <- "chip_chr21.txt"
    input_file <- "input_chr21.txt"
    m_file     <- "M_chr21.txt"
    gc_file    <- "GC_chr21.txt"
    n_file     <- "N_chr21.txt"
    
    # Verify that all required input files exist in the working directory
    required_files <- c(chip_file, input_file, m_file, gc_file, n_file)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("The following required input files are missing from the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # 1. Read bin-level data with genomic features
    # Adapted from documented code to read local files instead of system.file paths
    exampleBinData <- readBins( type=c("chip","input","M","GC","N"),
        fileName=c( chip_file,
        input_file,
        m_file,
        gc_file,
        n_file ) )
    
    # 2. Fit MOSAiCS model with TS (Two-Sample with genomic features) analysis
    exampleFit <- mosaicsFit( exampleBinData, analysisType="TS", bgEst="automatic" )
    
    # Bridge the vignette's variable naming discrepancy (exampleFit vs OneSampleFit)
    # to ensure the exact documented call to mosaicsPeak runs successfully.
    OneSampleFit <- exampleFit
    
    # 3. Call peaks
    OneSamplePeak <- mosaicsPeak( OneSampleFit, signalModel="2S", FDR=0.05,
    maxgap=200, minsize=50, thres=10 )
    
    # 4. Write meaningful output files
    # Export peak calling results in standard formats
    export( OneSamplePeak, type="txt", filename="mosaics_peaks.txt" )
    export( OneSamplePeak, type="bed", filename="mosaics_peaks.bed" )
    export( OneSamplePeak, type="gff", filename="mosaics_peaks.gff" )
    
    # Save R objects for downstream analysis
    saveRDS( exampleBinData, file="mosaics_bin_data.rds" )
    saveRDS( exampleFit, file="mosaics_fit.rds" )
    saveRDS( OneSamplePeak, file="mosaics_peaks.rds" )
    
    # Generate diagnostic and exploratory plots
    pdf( "mosaics_plots.pdf", width=8, height=8 )
    tryCatch({
      plot( exampleBinData, plotType="M" )
      plot( exampleBinData, plotType="GC" )
      plot( exampleBinData, plotType="M|input" )
      plot( exampleBinData, plotType="GC|input" )
      plot( exampleFit )
    }, error = function(e) {
      warning("Some diagnostic plots could not be generated: ", e\$message)
    })
    dev.off()
    
    cat("MOSAiCS pipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES":',
        paste0('    mosaics: ', as.character(packageVersion('mosaics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_sample_with_genomic_features.csv versions.yml
    """
}

workflow BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_chr21.txt, input_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt ] ]

    main:
    BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES(ch_input)

    emit:
    tables   = BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES.out.tables
    plots    = BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES.out.plots
    objects  = BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES.out.objects
    versions = BIOC_MOSAICS_TWO_SAMPLE_WITH_GENOMIC_FEATURES.out.versions
}
