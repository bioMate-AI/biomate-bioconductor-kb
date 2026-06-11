#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alpsnmr — older_peak_integration
// Process raw 1D NMR spectra using the older API workflow to perform baseline removal, alignment, normalization, and direct peak integration.
// Input: zip_files.zip, dummy_metadata.xlsx
// Container: quay.io/biocontainers/bioconductor-alpsnmr:4.12.0--r45h575d39b_0
// R packages: AlpsNMR, BiocParallel, fs, ggplot2, readxl
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION {
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
    .bm_deps <- c("AlpsNMR", "BiocParallel", "fs", "ggplot2", "readxl")
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
    library(BiocParallel)
    library(AlpsNMR)
    library(ggplot2)
    library(readxl)
    library(fs)
    
    # Register parallel backend
    register(SnowParam(workers = 2, exportglobals = FALSE), default = TRUE)
    
    # Define input file paths in the working directory
    metadata_file <- "dummy_metadata.xlsx"
    zip_archive <- "zip_files.zip"
    
    # Read metadata sheets
    exp_subj_id <- readxl::read_excel(metadata_file, sheet = 1)
    subj_id_age <- readxl::read_excel(metadata_file, sheet = 2)
    
    # Unzip the zip_files.zip to extract individual Bruker experiment directories/zips
    unzip_dir <- "unzipped_samples"
    if (dir.exists(unzip_dir)) {
      unlink(unzip_dir, recursive = TRUE)
    }
    dir.create(unzip_dir)
    utils::unzip(zip_archive, exdir = unzip_dir)
    
    # Identify sample files/directories to load
    zip_files <- fs::dir_ls(unzip_dir, glob = "*.zip")
    if (length(zip_files) == 0) {
      # If no nested zip files, look for directories
      zip_files <- fs::dir_ls(unzip_dir, type = "directory")
    }
    
    # Load samples
    dataset <- nmr_read_samples(sample_names = zip_files)
    
    # Add metadata
    dataset <- nmr_meta_add(dataset, metadata = exp_subj_id, by = "NMRExperiment")
    dataset <- nmr_meta_add(dataset, metadata = subj_id_age, by = "SubjectID")
    
    # Interpolate 1D spectra
    dataset <- nmr_interpolate_1D(dataset, axis = c(min = -0.5, max = 10, by = 2.3E-4))
    
    # Exclude uninformative regions (water and methanol)
    regions_to_exclude <- list(water = c(4.6, 5), methanol = c(3.33, 3.39))
    dataset <- nmr_exclude_region(dataset, exclude = regions_to_exclude)
    
    # Baseline removal
    dataset <- nmr_baseline_removal(dataset, lambda = 6, p = 0.01)
    
    # Peak detection
    peak_table <- nmr_detect_peaks(dataset,
                                   nDivRange_ppm = 0.1,
                                   scales = seq(1, 16, 2),
                                   baselineThresh = NULL, SNR.Th = 3)
    
    # Find reference spectrum and align
    nmr_exp_ref <- nmr_align_find_ref(dataset, peak_table)
    dataset_align <- nmr_align(dataset, peak_table, nmr_exp_ref, maxShift_ppm = 0.0015, acceptLostPeak = FALSE)
    
    # Normalize spectra using PQN
    dataset_norm <- nmr_normalize(dataset_align, method = "pqn")
    
    # Integrate peak positions
    peak_table_integration <- nmr_integrate_peak_positions(
      samples = dataset_norm,
      peak_pos_ppm = peak_table\$ppm,
      peak_width_ppm = 0.006)
    
    peak_table_integration <- get_integration_with_metadata(peak_table_integration)
    
    # Integrate specific regions (pyroglutamic acid) with baseline correction
    pyroglutamic_acid <- list(pyroglutamic_acid1 = c(4.19, 4.195),
                              pyroglutamic_acid2 = c(4.18, 4.186),
                              pyroglutamic_acid3 = c(4.175, 4.18),
                              pyroglutamic_acid4 = c(4.165, 4.172))
    regions_basel_corr_ds <- nmr_integrate_regions(dataset_norm, pyroglutamic_acid, fix_baseline = TRUE)
    regions_basel_corr_matrix <- nmr_data(regions_basel_corr_ds)
    
    # Identify blood regions
    ppm_to_assign <- c(4.060960203, 3.048970634, 2.405935596, 0.990616851, 0.986520147, 1.044258467)
    identification <- nmr_identify_regions_blood(ppm_to_assign)
    
    # Save outputs
    # 1. Peak table integration
    write.csv(as.data.frame(peak_table_integration), "peak_table_integration.csv", row.names = FALSE)
    
    # 2. Pyroglutamic acid baseline corrected matrix
    write.csv(as.data.frame(regions_basel_corr_matrix), "regions_basel_corr_matrix.csv", row.names = TRUE)
    
    # 3. Identification results
    write.csv(identification, "identification_results.csv", row.names = FALSE)
    
    # 4. Diagnostic plots
    pdf("nmr_pipeline_plots.pdf", width = 10, height = 7)
    
    # Plot alignment comparison
    p_align_before <- plot(dataset, chemshift_range = c(3.025, 3.063)) + ggtitle("Before Alignment")
    p_align_after <- plot(dataset_align, chemshift_range = c(3.025, 3.063)) + ggtitle("After Alignment")
    print(p_align_before)
    print(p_align_after)
    
    # Plot pyroglutamic acid region
    p_pyro <- plot(dataset_norm, chemshift_range = c(4.15, 4.20)) + ggtitle("Pyroglutamic Acid Region (Normalized)")
    print(p_pyro)
    
    dev.off()
    
    # Clean up temporary directory
    if (dir.exists(unzip_dir)) {
      unlink(unzip_dir, recursive = TRUE)
    }
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION":',
        paste0('        alpsnmr: ', as.character(packageVersion("alpsnmr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_older_peak_integration.csv versions.yml
    """
}

workflow BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zip_files.zip, dummy_metadata.xlsx ] ]

    main:
    BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION.out.tables
    plots    = BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION.out.plots
    objects  = BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION.out.objects
    versions = BIOC_ALPSNMR_OLDER_PEAK_INTEGRATION.out.versions
}
