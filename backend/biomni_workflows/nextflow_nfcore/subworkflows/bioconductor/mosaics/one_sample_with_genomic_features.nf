#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosaics — one_sample_with_genomic_features
// Identify peaks when no control sample is available, using genomic features (mappability, GC content, sequence ambiguity).
// Input: chip_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt
// Container: quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0
// R packages: mosaics
// Bioconductor: 3.20 | R: 4.4
// Requires: mosaics
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read bin-level data with genomic features
//  * 2. [Core Analysis] Fit MOSAiCS model with OS analysis
//  * 3. [Core Analysis] Call peaks

nextflow.enable.dsl = 2

process BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES {
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
    
    # Define the input files as specified by the user
    chip_file <- "chip_chr21.txt"
    mappability_file <- "M_chr21.txt"
    gc_file <- "GC_chr21.txt"
    ambiguity_file <- "N_chr21.txt"
    
    # Verify that all required input files exist in the working directory
    required_files <- c(chip_file, mappability_file, gc_file, ambiguity_file)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("The following required input files are missing from the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # 1. Read bin-level data with genomic features
    # (Adapted from documented code to read local user-provided files directly)
    exampleBinData <- readBins( type=c("chip","M","GC","N"),
        fileName=c( chip_file, mappability_file, gc_file, ambiguity_file ) )
    
    # Save the imported bin data object
    saveRDS(exampleBinData, file = "mosaics_bin_data.rds")
    
    # Generate exploratory plots for the bin-level data
    pdf("mosaics_exploratory_plots.pdf", width = 7, height = 7)
    tryCatch({
      plot( exampleBinData, plotType="M" )
    }, error = function(e) {
      warning("Could not plot Mappability vs ChIP: ", e\$message)
    })
    tryCatch({
      plot( exampleBinData, plotType="GC" )
    }, error = function(e) {
      warning("Could not plot GC content vs ChIP: ", e\$message)
    })
    dev.off()
    
    # 2. Fit MOSAiCS model with OS (One-Sample) analysis
    # (Reproduced exactly as documented)
    exampleFit <- mosaicsFit( exampleBinData, analysisType="OS", bgEst="automatic" )
    
    # Save the fitted model object
    saveRDS(exampleFit, file = "mosaics_fit.rds")
    
    # Generate Goodness of Fit (GOF) plot
    pdf("mosaics_gof_plot.pdf", width = 7, height = 7)
    tryCatch({
      plot(exampleFit)
    }, error = function(e) {
      warning("Could not generate GOF plot: ", e\$message)
    })
    dev.off()
    
    # 3. Call peaks
    # (Reproduced exactly as documented)
    examplePeak <- mosaicsPeak( exampleFit, signalModel="2S", FDR=0.05,
    maxgap=200, minsize=50, thres=10 )
    
    # Save the peak calling object
    saveRDS(examplePeak, file = "mosaics_peaks.rds")
    
    # Export peak calling results to standard formats
    export( examplePeak, type="txt", filename="mosaics_peaks.txt" )
    export( examplePeak, type="bed", filename="mosaics_peaks.bed" )
    export( examplePeak, type="gff", filename="mosaics_peaks.gff" )
    
    # Print summary of identified peaks to the console
    print(examplePeak)

    writeLines(c(
        '"BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES":',
        paste0('    mosaics: ', as.character(packageVersion('mosaics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_sample_with_genomic_features.csv versions.yml
    """
}

workflow BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt ] ]

    main:
    BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES(ch_input)

    emit:
    tables   = BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES.out.tables
    plots    = BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES.out.plots
    objects  = BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES.out.objects
    versions = BIOC_MOSAICS_ONE_SAMPLE_WITH_GENOMIC_FEATURES.out.versions
}
