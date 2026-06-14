#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alpsnmr — modern_peak_clustering
// Process raw 1D NMR spectra using the modern peak clustering workflow to generate a clean, aligned, and normalized peak table.
// Input: zip_files.zip, dummy_metadata.xlsx
// Container: quay.io/biocontainers/bioconductor-alpsnmr:4.12.0--r45h575d39b_0
// R packages: BiocParallel, AlpsNMR, dplyr, ggplot2, readxl
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-alpsnmr:4.12.0--r45h575d39b_0"

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
    .bm_deps <- c("BiocParallel", "AlpsNMR", "dplyr", "ggplot2", "readxl")
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
    
    library(dplyr)
    library(ggplot2)
    library(readxl)
    library(BiocParallel)
    library(AlpsNMR)
    
    # Enable parallelization
    register(SnowParam(workers = 2, exportglobals = FALSE), default = TRUE)
    
    # --- Load samples from user input zip_files.zip ---
    unzip_dir <- "unzipped_spectra"
    if (!dir.exists(unzip_dir)) {
      dir.create(unzip_dir)
    }
    unzip("zip_files.zip", exdir = unzip_dir)
    
    # Find zip files or Bruker directories recursively
    zip_files <- fs::dir_ls(unzip_dir, recurse = TRUE, glob = "*.zip")
    if (length(zip_files) == 0) {
      acqus_files <- fs::dir_ls(unzip_dir, recurse = TRUE, glob = "*acqus")
      if (length(acqus_files) > 0) {
        zip_files <- unique(fs::path_dir(acqus_files))
      } else {
        zip_files <- fs::dir_ls(unzip_dir, type = "directory", recurse = TRUE)
      }
    }
    
    dataset <- nmr_read_samples(sample_names = zip_files)
    
    # --- Add metadata ---
    annotations <- readxl::read_excel("dummy_metadata.xlsx")
    dataset <- nmr_meta_add(dataset, metadata = annotations, by = "NMRExperiment")
    
    # --- Interpolate 1D spectra ---
    dataset <- nmr_interpolate_1D(dataset, axis = c(min = -0.5, max = 10))
    
    # --- Exclude uninformative regions ---
    regions_to_exclude <- list(water = c(4.6, 5), methanol = c(3.33, 3.39))
    dataset <- nmr_exclude_region(dataset, exclude = regions_to_exclude)
    
    # --- Robust PCA outlier detection ---
    pca_outliers_rob <- nmr_pca_outliers_robust(dataset, ncomp = 3)
    
    pdf("pca_outliers_plot.pdf")
    nmr_pca_outliers_plot(dataset, pca_outliers_rob)
    dev.off()
    
    # --- Baseline estimation ---
    dataset <- nmr_baseline_estimation(dataset, lambda = 9, p = 0.01)
    
    # --- Baseline threshold calculation ---
    baselineThresh <- nmr_baseline_threshold(dataset, range_without_peaks = c(9.5, 10), method = "median3mad")
    
    # --- Initial peak detection ---
    peak_list_initial <- nmr_detect_peaks(
        dataset,
        nDivRange_ppm = 0.1,
        scales = seq(1, 16, 2),
        baselineThresh = baselineThresh,
        SNR.Th = 3,
        fit_lorentzians = TRUE
    )
    
    # --- Filter/accept peaks ---
    peak_list_initial_accepted <- peaklist_accept_peaks(
        peak_list_initial,
        dataset,
        area_min = 50, 
        keep_rejected = FALSE,
        verbose = TRUE
    )
    
    # --- Find reference spectrum ---
    NMRExp_ref <- nmr_align_find_ref(dataset, peak_list_initial_accepted)
    
    # --- Align spectra ---
    dataset_align <- nmr_align(
        nmr_dataset = dataset, 
        peak_data = peak_list_initial_accepted, 
        NMRExp_ref = NMRExp_ref, 
        maxShift_ppm = 0.0015, 
        acceptLostPeak = TRUE
    )
    
    # --- Normalize spectra ---
    dataset_norm <- nmr_normalize(dataset_align, method = "pqn")
    
    # --- Recalculate baseline threshold and detect peaks on ---
    baselineThresh <- nmr_baseline_threshold(dataset_norm, range_without_peaks = c(9.5, 10), method = "median3mad")
    
    peak_list_for_clustering_unfiltered <- nmr_detect_peaks(
        dataset_norm,
        nDivRange_ppm = 0.1,
        scales = seq(1, 16, 2),
        baselineThresh = baselineThresh,
        SNR.Th = 3,
        fit_lorentzians = TRUE,
        verbose = TRUE
    )
    
    peak_list_for_clustering <- peaklist_accept_peaks(
        peak_list_for_clustering_unfiltered,
        dataset_norm,
        area_min = 50, 
        keep_rejected = FALSE,
        verbose = TRUE
    )
    
    # --- Peak clustering ---
    clustering <- nmr_peak_clustering(peak_list_for_clustering, verbose = TRUE)
    peak_list_clustered <- clustering\$peak_data
    
    # --- Build peak table ---
    peak_table <- nmr_build_peak_table(peak_list_clustered, dataset_norm)
    
    # --- Extract peak matrix ---
    peak_matrix <- nmr_data(peak_table)
    
    # Save outputs
    saveRDS(peak_table, "peak_table.rds")
    write.csv(as.data.frame(peak_table), "peak_table.csv", row.names = FALSE)
    write.csv(peak_matrix, "peak_matrix.csv", row.names = TRUE)
    saveRDS(clustering, "clustering_results.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING":',
        paste0('        alpsnmr: ', as.character(packageVersion("alpsnmr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_modern_peak_clustering.csv versions.yml
    """
}

workflow BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zip_files.zip, dummy_metadata.xlsx ] ]

    main:
    BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING.out.tables
    plots    = BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING.out.plots
    objects  = BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING.out.objects
    versions = BIOC_ALPSNMR_MODERN_PEAK_CLUSTERING.out.versions
}
