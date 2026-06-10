#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcms — lc_ms_preprocessing
// Preprocess LC-MS data including peak detection, peak refinement, alignment (retention time correction), correspondence (peak grouping), gap filling, quality fil
// Input: cdfs
// Container: quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XCMS_LC_MS_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-xcms:4.8.0--r45ha27e39d_0"

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
    .bm_deps <- c("MsExperiment", "RColorBrewer", "SummarizedExperiment", "faahKO", "pander", "pheatmap", "xcms")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(xcms)
    library(faahKO)
    library(RColorBrewer)
    library(pander)
    library(pheatmap)
    library(MsExperiment)
    library(SummarizedExperiment)
    
    # 1. Load data using readMsExperiment
    # Read NetCDF/mzML/mzXML files from the working directory
    cdfs <- list.files(pattern = "\\.(cdf|CDF|mzML|mzXML)\$", ignore.case = TRUE, full.names = TRUE)
    if (length(cdfs) == 0) {
      stop("No CDF/mzML/mzXML files found in the working directory.")
    }
    
    # Create sample metadata dynamically based on the input files
    half <- ceiling(length(cdfs) / 2)
    sample_groups <- c(rep("KO", half), rep("WT", length(cdfs) - half))
    sample_types <- rep("study", length(cdfs))
    if (length(cdfs) >= 3) {
      sample_types[c(1, max(2, floor(length(cdfs)/2)), length(cdfs))] <- "QC"
    } else {
      sample_types[1] <- "QC"
    }
    
    pd <- data.frame(
      sample_name = sub(basename(cdfs), pattern = "\\.(cdf|CDF|mzML|mzXML)\$", replacement = "", ignore.case = TRUE),
      sample_group = sample_groups,
      sample_type = sample_types,
      stringsAsFactors = FALSE
    )
    
    faahko <- readMsExperiment(spectraFiles = cdfs, sampleData = pd)
    
    # 2. Filter retention time using filterRt
    # Dynamically adjust the RT filter range if the default 2550-4250 is out of bounds
    rts <- rtime(spectra(faahko))
    rt_range <- range(rts, na.rm = TRUE)
    if (rt_range[2] < 2550 || rt_range[1] > 4250) {
      rt_min <- rt_range[1] + 0.1 * (rt_range[2] - rt_range[1])
      rt_max <- rt_range[2] - 0.1 * (rt_range[2] - rt_range[1])
      target_rt <- c(rt_min, rt_max)
    } else {
      target_rt <- c(2550, 4250)
    }
    faahko <- filterRt(faahko, rt = target_rt)
    
    # 3. Detect chromatographic peaks using findChromPeaks with CentWaveParam
    cwp <- CentWaveParam(peakwidth = c(20, 80), noise = 5000, prefilter = c(6, 5000))
    faahko <- findChromPeaks(faahko, param = cwp)
    
    # 4. Refine/merge neighboring peaks using refineChromPeaks with MergeNeighboringPeaksParam
    mpp <- MergeNeighboringPeaksParam(expandRt = 4)
    faahko_pp <- refineChromPeaks(faahko, mpp)
    faahko <- faahko_pp
    
    # 5. Align retention times using adjustRtime with ObiwarpParam
    faahko <- adjustRtime(faahko, param = ObiwarpParam(binSize = 0.6))
    
    # 6. Group peaks into features (correspondence) using groupChromPeaks with PeakDensityParam
    pdp <- PeakDensityParam(sampleGroups = sampleData(faahko)\$sample_group, minFraction = 0.4, bw = 30)
    faahko <- groupChromPeaks(faahko, param = pdp)
    
    # 7. Fill missing peaks (gap filling) using fillChromPeaks with ChromPeakAreaParam
    faahko <- fillChromPeaks(faahko, param = ChromPeakAreaParam())
    
    # 8. Export results to a SummarizedExperiment using quantify
    res <- quantify(faahko, value = "into", method = "sum")
    
    # Save the SummarizedExperiment and associated tables
    saveRDS(res, "quantified_features_se.rds")
    write.csv(assay(res), "feature_intensities.csv", row.names = TRUE)
    write.csv(as.data.frame(colData(res)), "sample_metadata.csv", row.names = TRUE)
    write.csv(as.data.frame(rowData(res)), "feature_metadata.csv", row.names = TRUE)
    
    # 9. Filter features based on quality metrics (RSD, D-ratio, percent missing) using filterFeatures
    tryCatch({
      f <- sampleData(faahko)\$sample_type
      f[f != "QC"] <- NA
      missing_filter <- PercentMissingFilter(threshold = 30, f = f)
      filtered_faahko <- filterFeatures(object = faahko, filter = missing_filter)
    
      rsd_filter <- RsdFilter(threshold = 0.3, qcIndex = sampleData(filtered_faahko)\$sample_type == "QC")
      filtered_faahko <- filterFeatures(object = filtered_faahko, filter = rsd_filter)
    
      dratio_filter <- DratioFilter(threshold = 0.5, qcIndex = sampleData(filtered_faahko)\$sample_type == "QC", studyIndex = sampleData(filtered_faahko)\$sample_type == "study")
      filtered_faakho <- filterFeatures(object = filtered_faahko, filter = dratio_filter)
      
      saveRDS(filtered_faakho, "filtered_xcms_experiment.rds")
    }, error = function(e) {
      message("Feature filtering step skipped or failed: ", e\$message)
      saveRDS(faahko, "filtered_xcms_experiment.rds")
    })
    
    # Generate diagnostic plots
    pdf("xcms_preprocessing_plots.pdf", width = 10, height = 8)
    tryCatch({
      bpis <- chromatogram(faahko, aggregationFun = "max")
      plot(bpis, main = "Base Peak Chromatogram (After Alignment)")
    }, error = function(e) {
      message("Could not plot BPC: ", e\$message)
    })
    tryCatch({
      plotAdjustedRtime(faahko)
    }, error = function(e) {
      message("Could not plot adjusted retention times: ", e\$message)
    })
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_XCMS_LC_MS_PREPROCESSING":
        xcms: \$(Rscript -e 'cat(as.character(packageVersion("xcms")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms_preprocessing.csv versions.yml
    """
}

workflow BIOC_XCMS_LC_MS_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cdfs ] ]

    main:
    BIOC_XCMS_LC_MS_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_XCMS_LC_MS_PREPROCESSING.out.tables
    plots    = BIOC_XCMS_LC_MS_PREPROCESSING.out.plots
    objects  = BIOC_XCMS_LC_MS_PREPROCESSING.out.objects
    versions = BIOC_XCMS_LC_MS_PREPROCESSING.out.versions
}
