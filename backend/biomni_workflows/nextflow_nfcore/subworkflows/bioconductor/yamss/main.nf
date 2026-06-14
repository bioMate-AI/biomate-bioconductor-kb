#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: yamss — lcms_preprocessing_and_differential_analysis
// Preprocess raw LC/MS metabolomics data, detect and quantify peaks, and perform differential abundance analysis.
// Input: files, colData
// Container: quay.io/biocontainers/bioconductor-yamss:1.36.0--r45hdfd78af_0
// R packages: S4Vectors, mtbls2, yamss
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: density plot

nextflow.enable.dsl = 2

process BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-yamss:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("S4Vectors", "mtbls2", "yamss")
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
    
    # Load required libraries
    library(yamss)
    library(S4Vectors)
    
    # ==========================================
    # 1. Read User Inputs
    # ==========================================
    # The pipeline expects 'colData.csv' or 'colData.rds' in the working directory.
    # It also expects raw mass spectrometry files (.mzML or .mzXML) in the working directory or specified in colData.
    
    if (file.exists("colData.csv")) {
      colData_df <- read.csv("colData.csv", stringsAsFactors = FALSE)
      colData <- DataFrame(colData_df)
    } else if (file.exists("colData.rds")) {
      colData <- readRDS("colData.rds")
    } else {
      stop("Error: Required input 'colData.csv' or 'colData.rds' not found in the working directory.")
    }
    
    # Determine raw mass spectrometry files
    if ("file" %in% colnames(colData)) {
      files <- colData\$file
    } else if ("filePath" %in% colnames(colData)) {
      files <- colData\$filePath
    } else {
      # Fallback: list mzML/mzXML files in the working directory
      files <- list.files(pattern = "\\\\.(mzML|mzXML)\$", ignore.case = TRUE, full.names = TRUE)
    }
    
    if (length(files) == 0) {
      stop("Error: No raw mass spectrometry files (.mzML or .mzXML) found.")
    }
    
    # Ensure colData has the required columns
    if (!"sampClasses" %in% colnames(colData)) {
      if ("class" %in% colnames(colData)) {
        colData\$sampClasses <- colData\$class
      } else if ("group" %in% colnames(colData)) {
        colData\$sampClasses <- colData\$group
      } else {
        stop("Error: colData must contain a 'sampClasses' column representing sample groups.")
      }
    }
    
    if (!"ionmode" %in% colnames(colData)) {
      colData\$ionmode <- "pos"
    }
    
    classes <- colData\$sampClasses
    
    # ==========================================
    # 2. Preprocessing and Analysis (yamss Workflow)
    # ==========================================
    
    # --- Read raw mass spectrometry data ---
    cmsRaw <- readMSdata(files = files, colData = colData, mzsubset = c(500, 520), verbose = TRUE)
    
    # --- Preprocess raw data and estimate bivariate kernel density ---
    cmsProc <- bakedpi(cmsRaw, dbandwidth = c(0.01, 10), dgridstep = c(0.01, 1),
                       outfileDens = NULL, dortalign = TRUE, mzsubset = c(500, 520), verbose = TRUE)
    
    # --- Call peak bounds and quantify peaks ---
    cmsSlice <- slicepi(cmsProc, cutoff = NULL, verbose = TRUE)
    
    # --- Perform differential abundance analysis ---
    dr <- diffrep(cmsSlice, classes = classes)
    
    # --- Extract peak bounds and identify top peaks ---
    num_peaks <- min(10, nrow(dr))
    if (num_peaks > 0) {
      topPeaks <- as.numeric(rownames(dr)[1:num_peaks])
      bounds <- peakBounds(cmsSlice)
      idx <- match(topPeaks, bounds[,"peaknum"])
      top_bounds <- bounds[idx, , drop = FALSE]
    } else {
      topPeaks <- numeric(0)
      bounds <- peakBounds(cmsSlice)
      top_bounds <- bounds[0, , drop = FALSE]
    }
    
    # --- Density estimation and visualization ---
    dmat <- densityEstimate(cmsProc)
    
    if (length(topPeaks) > 0 && !is.na(idx[1])) {
      mzrange <- c(bounds[idx[1], "mzmin"], bounds[idx[1], "mzmax"])
      scanrange <- c(bounds[idx[1], "scanmin"], bounds[idx[1], "scanmax"])
      
      # Save density region plot to PDF
      pdf("density_region_plot.pdf", width = 7, height = 7)
      tryCatch({
        plotDensityRegion(cmsProc, mzrange = mzrange + c(-0.5, 0.5), scanrange = scanrange + c(-30, 30))
      }, error = function(e) {
        warning("Could not plot density region: ", e\$message)
      })
      dev.off()
    }
    
    # --- Alternative peak slicing thresholds ---
    cmsSlice2 <- slicepi(cmsProc, densityCutoff(cmsSlice) * 0.99)
    dqs <- densityQuantiles(cmsProc)
    cmsSlice3 <- slicepi(cmsProc, dqs["98.5%"])
    
    # ==========================================
    # 3. Export Results
    # ==========================================
    
    # Save tabular outputs
    write.csv(as.data.frame(dr), "differential_abundance_results.csv", row.names = TRUE)
    write.csv(as.data.frame(bounds), "all_peaks_bounds.csv", row.names = FALSE)
    write.csv(as.data.frame(top_bounds), "top_peaks_bounds.csv", row.names = FALSE)
    
    # Save processed R objects
    saveRDS(cmsProc, "cmsProc.rds")
    saveRDS(cmsSlice, "cmsSlice.rds")
    saveRDS(cmsSlice2, "cmsSlice2.rds")
    saveRDS(cmsSlice3, "cmsSlice3.rds")
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS":',
        paste0('        yamss: ', as.character(packageVersion("yamss")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lcms_preprocessing_and_differential_analysis.csv versions.yml
    """
}

workflow BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files, colData ] ]

    main:
    BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_YAMSS_LCMS_PREPROCESSING_AND_DIFFERENTIAL_ANALYSIS.out.versions
}
