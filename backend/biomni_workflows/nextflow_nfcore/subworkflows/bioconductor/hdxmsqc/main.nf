#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hdxmsqc — hdx_ms_quality_control
// Perform a complete quality control assessment on HDX-MS data, from raw HDExaminer output to a consolidated QC summary table.
// Input: <ELN55049_AllResultsTables_Uncurated.csv, BRD4_RowChecked_20220628_HDsite.csv, BRD4_RowChecked_20220628_HDE.csv
// Container: quay.io/biocontainers/bioconductor-hdxmsqc:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: QFeatures, RColorBrewer, S4Vectors, Spectra, dplyr, ggplot2, hdxmsqc, patchwork, pheatmap, tidyr
// Visualizations: heatmap
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] <1. Load and tidy HDExaminer data
//  * 2. [Core Analysis] Convert data to a QFeatures object
//  * 3. [Visualization & Output] Visualize data and missingness
//  * 4. [Core Analysis] Filter and impute missing values
//  * 5. [Visualization & Output] Compute and plot mass errors
//  * 6. [Visualization & Output] Detect and plot intensity outliers
//  * 7. [Visualization & Output] Analyze and plot retention time outliers
//  * 8. [Visualization & Output] Compute and plot monotonicity statistics
//  * 9. [Visualization & Output] Analyze and plot ion mobility outliers
//  * 10. [Core Analysis] Calculate charge state correlations
//  * 11. [Core Analysis] Assess replicate correlation and outliers
//  * 12. [Core Analysis] Check sequence overlap compatibility
//  * 13. [Core Analysis] Compare empirical and theoretical spectra
//  * 14. [Core Analysis] Generate a consolidated quality control table>

nextflow.enable.dsl = 2

process BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("hdxmsqc", "S4Vectors", "dplyr", "tidyr", "QFeatures", "RColorBrewer", "ggplot2", "MASS", "pheatmap", "Spectra", "patchwork")
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
    
    # Load required packages
    suppressMessages(library(hdxmsqc))
    suppressMessages(library(S4Vectors))
    suppressMessages(library(dplyr))
    suppressMessages(library(tidyr))
    suppressMessages(library(QFeatures))
    suppressMessages(library(RColorBrewer))
    suppressMessages(library(ggplot2))
    suppressMessages(library(MASS))
    suppressMessages(library(pheatmap))
    suppressMessages(library(Spectra))
    suppressMessages(library(patchwork))
    
    # ==========================================
    # 1. Load and tidy HDExaminer data
    # ==========================================
    message("Loading uncurated HDX-MS results...")
    BRD4uncurated <- data.frame(read.csv("ELN55049_AllResultsTables_Uncurated.csv"))
    
    message("Processing HDExaminer file...")
    BRD4uncurated_wide <- processHDE(HDExaminerFile = BRD4uncurated,
                                     proteinStates = c("wt", "iBET"))
    
    # ==========================================
    # 2. Convert data to a QFeatures object
    # ==========================================
    message("Converting to QFeatures object...")
    i <- grep(pattern = "X..Deut", x = names(BRD4uncurated_wide))
    
    BRD4df <- readQFeatures(assayData = BRD4uncurated_wide,
                            ecol = i,
                            names = "Deuteration",
                            fnames = "fnames")
    
    # ==========================================
    # 3. Visualize data and missingness
    # ==========================================
    message("Generating initial visualizations...")
    pdf("heatmap_deuteration.pdf", width = 10, height = 8)
    pheatmap(assay(BRD4df), cluster_rows = FALSE, scale = "row")
    dev.off()
    
    pdf("missingness_raw.pdf", width = 8, height = 6)
    plotMissing(object = BRD4df)
    dev.off()
    
    # ==========================================
    # 4. Filter and impute missing values
    # ==========================================
    message("Filtering and imputing missing values...")
    BRD4df_filtered <- isMissingAtRandom(object = BRD4df)
    
    pdf("missingness_filtered.pdf", width = 8, height = 6)
    plotMissing(object = BRD4df_filtered)
    dev.off()
    
    BRD4df_filtered_imputed <- impute(BRD4df_filtered, method = "zero", i = 1)
    
    # ==========================================
    # 5. Compute and plot mass errors
    # ==========================================
    message("Computing mass errors...")
    massError <- computeMassError(object = BRD4df_filtered_imputed)
    
    pdf("mass_error.pdf", width = 8, height = 6)
    plotMassError(object = BRD4df_filtered_imputed)
    dev.off()
    
    # ==========================================
    # 6. Detect and plot intensity outliers
    # ==========================================
    message("Detecting intensity outliers...")
    intensityOutlier <- intensityOutliers(object = BRD4df_filtered_imputed)
    
    pdf("intensity_outliers.pdf", width = 8, height = 6)
    plotIntensityOutliers(object = BRD4df_filtered_imputed)
    dev.off()
    
    # ==========================================
    # 7. Analyze and plot retention time outliers
    # ==========================================
    message("Analyzing retention time outliers...")
    dfrt <- rTimeOutliers(object = BRD4df_filtered_imputed)
    
    pdf("retention_time_outliers.pdf", width = 10, height = 6)
    rt_plots <- plotrTimeOutliers(object = BRD4df_filtered_imputed)
    if (is.list(rt_plots) && all(c("leftRTgg", "rightRTgg") %in% names(rt_plots))) {
      print(rt_plots\$leftRTgg + rt_plots\$rightRTgg)
    } else {
      print(rt_plots)
    }
    dev.off()
    
    # ==========================================
    # 8. Compute and plot monotonicity statistics
    # ==========================================
    message("Computing monotonicity statistics...")
    experiment <- c("wt", "iBET")
    timepoints <- rep(c(0, 15, 60, 600, 3600, 14000), each = 3)
    
    monoStat <- computeMonotoneStats(object = BRD4df_filtered_imputed,
                                     experiment = experiment, 
                                     timepoints = timepoints)
    
    pdf("monotonicity_stats.pdf", width = 10, height = 6)
    out <- plotMonotoneStat(object = BRD4df_filtered_imputed,
                            experiment = experiment, 
                            timepoints = timepoints)
    if (is.list(out)) {
      for (p in out) {
        if (inherits(p, "ggplot") || inherits(p, "grob")) {
          print(p)
        }
      }
    } else {
      print(out)
    }
    dev.off()
    
    # ==========================================
    # 9. Analyze and plot ion mobility outliers
    # ==========================================
    message("Analyzing ion mobility outliers...")
    imTimeOut <- imTimeOutlier(object = BRD4df_filtered_imputed)
    
    pdf("ion_mobility_outliers.pdf", width = 10, height = 6)
    im_plots <- plotImTimeOutlier(object = BRD4df_filtered_imputed)
    if (is.list(im_plots) && all(c("leftIMSgg", "rightIMSgg") %in% names(im_plots))) {
      print(im_plots\$leftIMSgg + im_plots\$rightIMSgg)
    } else {
      print(im_plots)
    }
    dev.off()
    
    # ==========================================
    # 10. Calculate charge state correlations
    # ==========================================
    message("Calculating charge state correlations...")
    csCor <- chargeCorrelationHdx(object = BRD4df_filtered_imputed,
                                  experiment = experiment,
                                  timepoints = timepoints)
    
    # ==========================================
    # 11. Assess replicate correlation and outliers
    # ==========================================
    message("Assessing replicate correlation and outliers...")
    replicateVar <- replicateCorrelation(object = BRD4df_filtered_imputed,
                                         experiment = experiment,
                                         timepoints = timepoints)
    
    replicateOut <- replicateOutlier(object = BRD4df_filtered_imputed,
                                     experiment = experiment,
                                     timepoints = timepoints)
    
    # ==========================================
    # 12. Check sequence overlap compatibility
    # ==========================================
    message("Checking sequence overlap compatibility...")
    tocheck <- compatibleUptake(object = BRD4df_filtered_imputed,
                                experiment = experiment,
                                timepoints = timepoints)
    
    # ==========================================
    # 13. Compare empirical and theoretical spectra
    # ==========================================
    message("Comparing empirical and theoretical spectra...")
    hdxsite <- data.frame(read.csv("BRD4_RowChecked_20220628_HDsite.csv",
                                   header = TRUE, fileEncoding = 'UTF-8-BOM'))
    BRD4matched <- read.csv("BRD4_RowChecked_20220628_HDE.csv",
                            header = TRUE, fileEncoding = 'UTF-8-BOM')
    
    spectraCompare <- spectraSimilarity(peaks = hdxsite,
                                        object = BRD4matched, 
                                        experiment = experiment,
                                        numSpectra = NULL)
    
    pdf("spectra_mirror.pdf", width = 8, height = 6)
    plotSpectraMirror(spectraCompare\$observedSpectra[1,], spectraCompare\$matchedSpectra[1,], ppm = 300)
    dev.off()
    
    # ==========================================
    # 14. Generate a consolidated quality control table
    # ==========================================
    message("Generating consolidated QC table...")
    qctable <- qualityControl(object = BRD4df_filtered_imputed, 
                               massError = massError,
                               intensityOutlier = intensityOutlier,
                               retentionOutlier = dfrt,
                               monotonicityStat = monoStat,
                               mobilityOutlier = imTimeOut,
                               chargeCorrelation = csCor,
                               replicateCorrelation = replicateVar,
                               replicateOutlier = replicateOut,
                               sequenceCheck = tocheck,
                               spectraCheck = spectraCompare,
                               experiment = experiment,
                               timepoints = timepoints )
    
    # Save final outputs
    write.csv(qctable, "hdx_ms_qc_summary.csv", row.names = FALSE)
    saveRDS(BRD4df_filtered_imputed, "BRD4df_filtered_imputed.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL":',
        paste0('    hdxmsqc: ', as.character(packageVersion('hdxmsqc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hdx_ms_quality_control.csv versions.yml
    """
}

workflow BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ <ELN55049_AllResultsTables_Uncurated.csv, BRD4_RowChecked_20220628_HDsite.csv, BRD4_RowChecked_20220628_HDE.csv ] ]

    main:
    BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL(ch_input)

    emit:
    tables   = BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL.out.tables
    plots    = BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL.out.plots
    objects  = BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL.out.objects
    versions = BIOC_HDXMSQC_HDX_MS_QUALITY_CONTROL.out.versions
}
