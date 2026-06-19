#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cardinal — msi_preprocessing_and_peak_extraction
// Import raw MSI data, apply sequential preprocessing steps, perform peak picking and alignment, and export the processed dataset.
// Input: continuous.imzML, processed.imzML
// Container: quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0
// R packages: Cardinal, cardinalworkflows
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0"

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
    .bm_deps <- c("Cardinal", "cardinalworkflows")
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
    library(Cardinal)
    
    # --- Read raw MSI data using readMSIData() ---
    # Reading the user-provided continuous and processed imzML files
    path_continuous <- "continuous.imzML"
    mse_tiny <- readMSIData(path_continuous)
    
    path_processed <- "processed.imzML"
    msa <- readMSIData(path_processed)
    
    # --- Queue preprocessing steps: normalize(), smooth(), ---
    mse_queue <- msa |>
    	normalize() |>
    	smooth() |>
    	reduceBaseline() |>
    	peakPick(SNR=6)
    
    # --- Preview queued processing using plot() ---
    # Saving the preview plot to a PDF file
    pdf("preprocessing_preview.pdf", width=9, height=6)
    tryCatch({
    	plot(mse_queue, coord=list(x=16, y=16), linewidth=2)
    }, error = function(e) {
    	warning("Could not plot at coord (16,16), attempting default plot: ", e\$message)
    	try(plot(mse_queue, linewidth=2))
    })
    dev.off()
    
    # --- Apply processing and align peaks across spectra using ---
    mse_proc <- peakAlign(mse_queue)
    
    # --- Filter peaks by frequency using subsetFeatures() ---
    mse_proc <- subsetFeatures(mse_proc, freq > 0.1)
    
    # --- Export the processed dataset to imzML using writeMSIData() ---
    imzfile <- "processed_output.imzML"
    if (file.exists(imzfile)) {
    	unlink(imzfile, recursive = TRUE)
    }
    writeMSIData(mse_proc, file=imzfile)
    
    # Read the exported dataset back to verify
    mse_re <- readMSIData(imzfile)
    
    # Save additional meaningful results
    # Save the processed MSImagingExperiment object as an RDS file
    saveRDS(mse_proc, file="processed_dataset.rds")
    
    # Export detected peak metadata (features) to CSV
    tryCatch({
    	peaks_df <- as.data.frame(featureData(mse_proc))
    	write.csv(peaks_df, file="detected_peaks.csv", row.names=FALSE)
    }, error = function(e) {
    	warning("Could not export feature data to CSV: ", e\$message)
    })
    
    # Export pixel metadata to CSV
    tryCatch({
    	pixel_df <- as.data.frame(pixelData(mse_proc))
    	write.csv(pixel_df, file="pixel_metadata.csv", row.names=FALSE)
    }, error = function(e) {
    	warning("Could not export pixel data to CSV: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION":',
        paste0('        cardinal: ', as.character(packageVersion("cardinal")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msi_preprocessing_and_peak_extraction.csv versions.yml
    """
}

workflow BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ continuous.imzML, processed.imzML ] ]

    main:
    BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION.out.tables
    plots    = BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION.out.plots
    objects  = BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION.out.objects
    versions = BIOC_CARDINAL_MSI_PREPROCESSING_AND_PEAK_EXTRACTION.out.versions
}
