#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AlpsNMR — untargeted_nmr_metabolomics_classic
// Process raw Bruker NMR data using the classic workflow with direct peak integration, baseline correction, and blood metabolite identification.
// Input: zip_files, dummy_metadata.xlsx
// Container: quay.io/biocontainers/bioconductor-alpsnmr:4.12.0--r45h575d39b_0
// Requires: AlpsNMR, BiocParallel, fs, ggplot2, readxl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load samples and metadata
//  * 2. [Core Analysis] Interpolate 1D spectra
//  * 3. [Core Analysis] Exclude uninformative regions
//  * 4. [Core Analysis] Remove baseline
//  * 5. [Core Analysis] Detect peaks
//  * 6. [Core Analysis] Align spectra
//  * 7. [Core Analysis] Normalize spectra
//  * 8. [Core Analysis] Integrate peaks by position or region
//  * 9. [Core Analysis] Identify blood metabolites

nextflow.enable.dsl = 2

process BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        library(BiocParallel)
        library(AlpsNMR)
        library(readxl)
        library(fs)
        library(ggplot2)
        
        # Register parallel backend
        register(SnowParam(workers = 2, exportglobals = FALSE), default = TRUE)
        
        # Define input files in the working directory
        MeOH_plasma_extraction_xlsx <- "dummy_metadata.xlsx"
        zip_files <- fs::dir_ls(".", glob = "*.zip")
        
        # Read metadata sheets
        exp_subj_id <- readxl::read_excel(MeOH_plasma_extraction_xlsx, sheet = 1)
        subj_id_age <- readxl::read_excel(MeOH_plasma_extraction_xlsx, sheet = 2)
        
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
        
        # Remove baseline
        dataset <- nmr_baseline_removal(dataset, lambda = 6, p = 0.01)
        
        # Detect peaks
        peak_table <- nmr_detect_peaks(dataset,
                                       nDivRange_ppm = 0.1,
                                       scales = seq(1, 16, 2),
                                       baselineThresh = NULL, SNR.Th = 3)
        
        # Align spectra
        nmr_exp_ref <- nmr_align_find_ref(dataset, peak_table)
        dataset_align <- nmr_align(dataset, peak_table, nmr_exp_ref, maxShift_ppm = 0.0015, acceptLostPeak = FALSE)
        
        # Normalize spectra
        dataset_norm <- nmr_normalize(dataset_align, method = "pqn")
        
        # Integrate peaks by position
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
        
        # Identify blood metabolites
        ppm_to_assign <- c(4.060960203, 3.048970634, 2.405935596, 0.990616851, 0.986520147, 1.044258467)
        identification <- nmr_identify_regions_blood(ppm_to_assign)
        
        # Save RDS objects
        saveRDS(dataset_norm, "normalized_dataset.rds")
        saveRDS(peak_table_integration, "peak_table_integration.rds")
        
        # Export integration tables and identification results to CSV
        write.csv(as.data.frame(peak_table_integration), "peak_table_integration.csv", row.names = TRUE)
        write.csv(as.data.frame(regions_basel_corr_matrix), "pyroglutamic_acid_integrated.csv", row.names = TRUE)
        write.csv(identification, "blood_metabolite_identification.csv", row.names = FALSE)
        
        # Generate diagnostic plots
        pdf("nmr_pipeline_plots.pdf", width = 10, height = 7)
        
        # Plot normalized spectra in a specific region
        tryCatch({
          print(plot(dataset_norm, chemshift_range = c(2.2, 2.8)) + ggplot2::ggtitle("Normalized Spectra (2.2 - 2.8 ppm)"))
        }, error = function(e) warning("Could not plot normalized spectra: ", e\$message))
        
        # Plot pyroglutamic acid region
        tryCatch({
          print(plot(dataset_norm, chemshift_range = c(4.15, 4.20)) + ggplot2::ggtitle("Pyroglutamic Acid Region"))
        }, error = function(e) warning("Could not plot pyroglutamic acid region: ", e\$message))
        
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC":',
        paste0('    AlpsNMR: ', as.character(packageVersion('AlpsNMR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_untargeted_nmr_metabolomics_classic.csv versions.yml
    """
}

workflow BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zip_files, dummy_metadata.xlsx ] ]

    main:
    BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC(ch_input)

    emit:
    tables   = BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC.out.tables
    plots    = BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC.out.plots
    objects  = BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC.out.objects
    versions = BIOC_ALPSNMR_UNTARGETED_NMR_METABOLOMICS_CLASSIC.out.versions
}
