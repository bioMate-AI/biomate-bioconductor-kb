#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TargetSearch — target_search_gcms_preprocessing
// Preprocess raw GC-MS data using TargetSearch by generating standard NetCDF files from input intensity matrices, performing retention index (RI) correction, libr
// Input: intensity.csv, coldata.csv
// Container: 2.12.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TargetSearch, ncdf4
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("TargetSearch", "ncdf4")
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
    library(TargetSearch)
    library(ncdf4)
    
    # ==========================================
    # --- Read Inputs & Generate Raw GC-MS NetCDF Files ---
    # ==========================================
    message("Stage 1: Reading inputs and generating dummy NetCDF files...")
    
    # Read the staged input files
    intensity_df <- read.csv("intensity.csv", row.names = 1, check.names = FALSE)
    coldata_df <- read.csv("coldata.csv")
    
    # Extract sample names and features
    samples_vec <- coldata_df\$sample
    features <- rownames(intensity_df)
    num_features <- length(features)
    
    # Define retention times (RT) and retention indices (RI) for features
    # Space features evenly between RT 240 and 360 seconds
    rt_spacing <- if (num_features > 1) 120 / (num_features - 1) else 10
    feature_rts <- 240 + (seq_len(num_features) - 1) * rt_spacing
    feature_ris <- feature_rts * 1000
    
    # Assign 3 characteristic masses to each feature
    feature_masses <- lapply(seq_len(num_features), function(j) {
      m1 <- 100 + (j %% 300)
      c(m1, m1 + 1, m1 + 2)
    })
    
    # Helper function to create a standard ANDI-MS NetCDF file
    create_dummy_cdf <- function(filename, scans, scan_data) {
      point_count <- sapply(scan_data, function(x) length(x\$mass))
      scan_index <- c(0, cumsum(point_count)[-length(point_count)])
      mass_values <- unlist(lapply(scan_data, function(x) x\$mass))
      intensity_values <- unlist(lapply(scan_data, function(x) x\$intensity))
      total_points <- length(mass_values)
    
      dim_scan <- ncdim_def("scan_number", "", 1:length(scans))
      dim_point <- ncdim_def("point_number", "", 1:total_points)
    
      var_rt <- ncvar_def("scan_acquisition_time", "seconds", dim_scan, prec="double")
      var_pcount <- ncvar_def("point_count", "count", dim_scan, prec="integer")
      var_sindex <- ncvar_def("scan_index", "index", dim_scan, prec="integer")
      var_mass <- ncvar_def("mass_values", "m/z", dim_point, prec="double")
      var_int <- ncvar_def("intensity_values", "counts", dim_point, prec="double")
    
      nc <- nc_create(filename, list(var_rt, var_pcount, var_sindex, var_mass, var_int))
      ncvar_put(nc, var_rt, scans)
      ncvar_put(nc, var_pcount, point_count)
      ncvar_put(nc, var_sindex, scan_index)
      ncvar_put(nc, var_mass, mass_values)
      ncvar_put(nc, var_int, intensity_values)
      nc_close(nc)
    }
    
    # Generate NetCDF files for each sample with simulated peaks
    scans <- 1:450
    for (s_name in samples_vec) {
      scan_data <- vector("list", length(scans))
      for (t in scans) {
        # Baseline noise point
        mass_list <- c(99)
        int_list <- c(5)
    
        # Add RI markers (FAMEs) at RT 220, 300, and 380
        if (t == 220 || t == 300 || t == 380) {
          mass_list <- c(mass_list, 87)
          int_list <- c(int_list, 10000)
        }
    
        # Add feature peaks
        for (j in seq_len(num_features)) {
          rt_j <- feature_rts[j]
          dist <- abs(t - rt_j)
          if (dist <= 1.5) {
            factor <- exp(- (dist^2) / 0.5)
            raw_val <- intensity_df[j, s_name]
            val <- max(100, as.numeric(raw_val)) * factor
    
            m <- feature_masses[[j]]
            mass_list <- c(mass_list, m)
            int_list <- c(int_list, round(c(val, val * 0.7, val * 0.4)))
          }
        }
    
        # Sort by mass
        ord <- order(mass_list)
        scan_data[[t]] <- list(mass = mass_list[ord], intensity = int_list[ord])
      }
    
      cdf_filename <- paste0(s_name, ".cdf")
      create_dummy_cdf(cdf_filename, scans, scan_data)
    }
    
    # ==========================================
    # --- Create TargetSearch Metadata Files ---
    # ==========================================
    message("Stage 2: Creating TargetSearch metadata files...")
    
    # Create samples.txt
    samples_df <- data.frame(
      CDF_FILE = paste0(samples_vec, ".cdf"),
      MEASUREMENT_DAY = rep("20260428", length(samples_vec)),
      SAMPLE_NAME = samples_vec
    )
    write.table(samples_df, "samples.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    # Create rimLimits.txt
    rim_lines <- c(
      "LowerLimit\tUpperLimit\tRIstandard",
      "210\t230\t220000",
      "290\t310\t300000",
      "370\t390\t380000"
    )
    writeLines(rim_lines, "rimLimits.txt")
    
    # Create library.txt
    lib_lines <- c("Name\tRI\tWin_1\tSEL_MASS\tTOP_MASS\tSPECTRUM")
    for (j in seq_len(num_features)) {
      name <- features[j]
      ri <- round(feature_ris[j])
      m <- feature_masses[[j]]
      sel_mass <- paste(m, collapse = ";")
      top_mass <- paste(m, collapse = ";")
      spectrum <- paste(paste0(m[1], ":999"), paste0(m[2], ":700"), paste0(m[3], ":400"))
      lib_lines <- c(lib_lines, paste(name, ri, "2000", sel_mass, top_mass, spectrum, sep = "\t"))
    }
    writeLines(lib_lines, "library.txt")
    
    # ==========================================
    # --- TargetSearch Preprocessing & RI Correction ---
    # ==========================================
    message("Stage 3: Running TargetSearch RI correction...")
    
    # Import samples and RI markers
    samples <- ImportSamples("samples.txt", CDFpath = ".", RIpath = ".")
    rimLimits <- ImportFameSettings("rimLimits.txt", mass = 87)
    
    # Convert to custom CDF4 format for faster processing
    samples <- ncdf4Convert(samples, path=".")
    
    # Perform peak picking and RI correction
    RImatrix <- RIcorrect(samples, rimLimits, IntThreshold = 50, pp.method = "ppc", Window = 5)
    
    # Identify FAME outliers
    outliers <- FAMEoutliers(samples, RImatrix, threshold = 3)
    
    # ==========================================
    # --- Library Search & Metabolite Profiling ---
    # ==========================================
    message("Stage 4: Performing library search and profiling...")
    
    # Import metabolite library
    lib <- ImportLibrary("library.txt", RI_dev = c(2000, 1000, 200), TopMasses = 3)
    
    # Update library RIs using sample medians
    lib <- medianRILib(samples, lib)
    
    # Search selective masses and calculate sample-specific RIs
    cor_RI <- sampleRI(samples, lib, r_thres = 0.90, method = "dayNorm")
    
    # Find all peaks matching library targets
    peakData <- peakFind(samples, lib, cor_RI)
    
    # Create metabolite profiles
    MetabProfile <- Profile(samples, lib, peakData, r_thres = 0.90, method = "dayNorm")
    
    # Clean up redundant profiles
    finalProfile <- ProfileCleanUp(MetabProfile, timeSplit = 500, r_thres = 0.90)
    
    # ==========================================
    # --- Export Results & Generate Diagnostic Plots ---
    # ==========================================
    message("Stage 5: Exporting results and generating plots...")
    
    # 1. Save Profile Info
    prof_info <- profileInfo(finalProfile)
    write.csv(prof_info, "profile_info.csv", row.names = FALSE)
    
    # 2. Save Final Quantified Intensities
    prof_int <- Intensity(finalProfile)
    write.csv(prof_int, "final_intensities.csv")
    
    # 3. Plot FAME (Retention Index Marker 1)
    pdf("fame_plot.pdf", width = 7, height = 5)
    plotFAME(samples, RImatrix, 1)
    dev.off()
    
    # 4. Plot Spectra Comparison (Head-to-Tail) for the first metabolite
    pdf("spectra_plot.pdf", width = 7, height = 5)
    plotSpectra(lib, peakData, libID = 1, type = "ht")
    dev.off()
    
    # 5. Plot Chromatographic Peak for the first metabolite in the first sample
    pdf("peak_plot.pdf", width = 7, height = 5)
    rawpeaks <- peakCDFextraction(paste0(samples_vec[1], ".cdf"))
    plotPeak(samples, lib, MetabProfile, rawpeaks, which.smp = 1, which.met = 1, corMass = FALSE)
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING":',
        paste0('    TargetSearch: ', as.character(packageVersion('TargetSearch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_target_search_gcms_preprocessing.csv versions.yml
    """
}

workflow BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING.out.tables
    plots    = BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING.out.plots
    objects  = BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING.out.objects
    versions = BIOC_TARGETSEARCH_TARGET_SEARCH_GCMS_PREPROCESSING.out.versions
}
