#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flagme — correlation_based_alignment
// Perform correlation-based alignment on peaks detected using XCMS.
// Input: cdfFiles
// Container: quay.io/biocontainers/bioconductor-flagme:1.66.0--r45h01b2380_0
// Requires: flagme, xcms
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a peaks dataset from raw CDF files using peaksDataset
//  * 2. [Core Analysis] Detect and add peaks using XCMS with addXCMSPeaks
//  * 3. [Core Analysis] Align peaks using correlationAlignment

nextflow.enable.dsl = 2

process BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("flagme", "xcms")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
    # Load required libraries
    library(flagme)
    library(xcms)
    
    # 1. Identify CDF files in the working directory
    cdfFiles <- list.files(pattern = "\\\\.(cdf|CDF)\$", full.names = TRUE)
    
    if (length(cdfFiles) == 0) {
      stop("Error: No NetCDF (.cdf or .CDF) files found in the working directory.")
    }
    
    # 2. Create peaks dataset from raw CDF files
    message("Creating peaks dataset...")
    pd.2 <- peaksDataset(cdfFiles, mz = seq(50, 550))
    
    # 3. Detect and add peaks using XCMS
    message("Detecting and adding XCMS peaks...")
    mfp <- xcms::MatchedFilterParam(fwhm = 10, snthresh = 5)
    pd.2 <- addXCMSPeaks(cdfFiles, pd.2, settings = mfp)
    
    # 4. Align peaks using correlationAlignment
    message("Performing correlation-based alignment...")
    mp <- correlationAlignment(object=pd.2, thr=0.85, D=20, penality=0.2,
                               normalize=TRUE, minFilter=1)
    
    # 5. Save results and generate outputs
    message("Saving results...")
    saveRDS(pd.2, "peaks_dataset_xcms.rds")
    saveRDS(mp, "correlation_alignment.rds")
    
    # Try to gather and save alignment info
    tryCatch({
      outList <- gatherInfo(pd.2, mp)
      saveRDS(outList, "alignment_info_list.rds")
      
      # Extract retention times
      rt_list <- lapply(outList, function(x) x\$rt)
      rt_list <- rt_list[!sapply(rt_list, is.null)]
      if (length(rt_list) > 0) {
        rtmat <- matrix(unlist(rt_list, use.names=FALSE),
                        nrow=length(rt_list), byrow=TRUE)
        colnames(rtmat) <- names(rt_list[[1]])
        write.csv(rtmat, "aligned_retention_times.csv", row.names=TRUE)
        message("Saved aligned retention times to 'aligned_retention_times.csv'")
      }
    }, error = function(e) {
      message("Note: Could not extract detailed alignment table (", e\$message, "). Saving raw alignment object instead.")
    })
    
    # Generate a diagnostic plot
    tryCatch({
      pdf("alignment_chromatogram_plot.pdf", width=10, height=7)
      plotChrom(pd.2, plotPeaks=TRUE, plotPeakLabels=TRUE)
      dev.off()
      message("Saved diagnostic plot to 'alignment_chromatogram_plot.pdf'")
    }, error = function(e) {
      message("Note: Could not generate plot (", e\$message, ")")
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT":',
        paste0('    flagme: ', as.character(packageVersion('flagme')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_based_alignment.csv versions.yml
    """
}

workflow BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cdfFiles ] ]

    main:
    BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT.out.tables
    plots    = BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT.out.plots
    objects  = BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT.out.objects
    versions = BIOC_FLAGME_CORRELATION_BASED_ALIGNMENT.out.versions
}
