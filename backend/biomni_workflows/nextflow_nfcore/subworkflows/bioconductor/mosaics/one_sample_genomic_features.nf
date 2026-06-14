#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosaics — one_sample_genomic_features
// Identify peaks when no matched control sample is available, using genomic features.
// Input: chip_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt
// Container: quay.io/biocontainers/bioconductor-mosaics:2.48.0--pl5321r45ha27e39d_0
// R packages: mosaics
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: mosaic plot

nextflow.enable.dsl = 2

process BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES {
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
    
    # Load required library
    library(mosaics)
    
    # Define input files from the working directory as specified by the user
    fileName <- c("chip_chr21.txt", "M_chr21.txt", "GC_chr21.txt", "N_chr21.txt")
    
    # --- Read bin-level data with genomic features ---
    message("Reading bin-level data...")
    exampleBinData <- readBins( type=c("chip","M","GC","N"), fileName=fileName )
    
    # Save RDS of bin data
    saveRDS(exampleBinData, "mosaics_bin_data.rds")
    
    # Generate exploratory plots
    message("Generating exploratory plots...")
    pdf("mosaics_exploratory_plots.pdf", width=8, height=6)
    tryCatch({
        plot( exampleBinData, plotType="M" )
    }, error = function(e) {
        message("Could not plot M: ", e\$message)
    })
    tryCatch({
        plot( exampleBinData, plotType="GC" )
    }, error = function(e) {
        message("Could not plot GC: ", e\$message)
    })
    dev.off()
    
    # --- Fit MOSAiCS model with OS (One-Sample) analysis type ---
    message("Fitting MOSAiCS model...")
    exampleFit <- mosaicsFit( exampleBinData, analysisType="OS", bgEst="automatic" )
    
    # Save RDS of fit
    saveRDS(exampleFit, "mosaics_fit.rds")
    
    # Generate Goodness of Fit (GOF) plot
    message("Generating GOF plot...")
    pdf("mosaics_gof_plot.pdf", width=8, height=6)
    tryCatch({
        plot(exampleFit)
    }, error = function(e) {
        message("Could not plot GOF: ", e\$message)
    })
    dev.off()
    
    # --- Call peaks ---
    message("Calling peaks...")
    examplePeak <- mosaicsPeak( exampleFit, signalModel="2S", FDR=0.05, maxgap=200, minsize=50, thres=10 )
    
    # Save RDS of peaks
    saveRDS(examplePeak, "mosaics_peaks.rds")
    
    # Export peak calling results to standard formats
    message("Exporting peak calling results...")
    export( examplePeak, type="txt", filename="peaks_one_sample.txt" )
    export( examplePeak, type="bed", filename="peaks_one_sample.bed" )
    
    # Write a summary text file of the peak calling results
    sink("mosaics_summary.txt")
    cat("=== MOSAiCS One-Sample Analysis Summary ===\n\n")
    print(examplePeak)
    sink()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES":',
        paste0('        mosaics: ', as.character(packageVersion("mosaics")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_sample_genomic_features.csv versions.yml
    """
}

workflow BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chip_chr21.txt, M_chr21.txt, GC_chr21.txt, N_chr21.txt ] ]

    main:
    BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES(ch_input)

    emit:
    tables   = BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES.out.tables
    plots    = BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES.out.plots
    objects  = BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES.out.objects
    versions = BIOC_MOSAICS_ONE_SAMPLE_GENOMIC_FEATURES.out.versions
}
