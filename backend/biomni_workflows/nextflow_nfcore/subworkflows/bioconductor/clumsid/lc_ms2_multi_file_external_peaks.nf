#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clumsid — lc_ms2_multi_file_external_peaks
// Extract MS2 spectra from multiple raw files, merge them using an external peak list, add annotations, and cluster them.
// Input: YH1_GA7_01_10463.mzML, AX1_GB5_01_10470.mzML, LP1_GB3_01_10467.mzML, BR1_GB6_01_10471.mzML, m_mtbls433_metabolite_profiling_mass_spectrometry_v2_maf.tsv
// Container: quay.io/biocontainers/bioconductor-clumsid:1.26.0--r45hdfd78af_0
// R packages: CluMSID, dplyr, magrittr, readr, stringr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-clumsid:1.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("CluMSID", "dplyr", "magrittr", "readr", "stringr")
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
    library(CluMSID)
    library(magrittr)
    library(dplyr)
    library(readr)
    library(stringr)
    
    # Define input file paths in the working directory
    YH1 <- "YH1_GA7_01_10463.mzML"
    AX1 <- "AX1_GB5_01_10470.mzML"
    LP1 <- "LP1_GB3_01_10467.mzML"
    BR1 <- "BR1_GB6_01_10471.mzML"
    raw_mtbls_df <- "m_mtbls433_metabolite_profiling_mass_spectrometry_v2_maf.tsv"
    
    # --- Extract MS2 spectra from multiple files and combine them ---
    message("Extracting MS2 spectra from raw files...")
    YH1list <- extractMS2spectra (YH1)
    AX1list <- extractMS2spectra (AX1)
    LP1list <- extractMS2spectra (LP1)
    BR1list <- extractMS2spectra (BR1)
    raw_oillist <- c (YH1list, AX1list, LP1list, BR1list)
    
    # --- Format the external peak table to match CluMSID ---
    message("Formatting external peak table...")
    mtbls_df <- readr :: read_delim (raw_mtbls_df, "\t" ) %>% 
      dplyr :: mutate ( metabolite_identification = stringr :: str_replace (metabolite_identification, "unknown" , "" )) %>% 
      dplyr :: mutate ( id = paste0 ( "M" , mass_to_charge, "T" , retention_time)) %>% 
      dplyr :: mutate ( retention_time = retention_time * 60 ) %>% 
      dplyr :: select (id, mass_to_charge, retention_time, metabolite_identification) %>% 
      dplyr :: rename ( mz = mass_to_charge, rt = retention_time, annotation = metabolite_identification)
    
    # --- Merge spectra matching the external peak table ---
    message("Merging MS2 spectra using external peak table...")
    oillist <- mergeMS2spectra (raw_oillist, peaktable = mtbls_df[, 1 : 3 ], exclude_unmatched = TRUE , rt_tolerance = 60 , mz_tolerance = 3e-5 )
    
    # --- Add external annotations ---
    message("Adding annotations...")
    fl <- featureList (oillist)
    fl_annos <- dplyr :: left_join (fl, mtbls_df, by = "id" )
    annolist <- addAnnotations (oillist, fl_annos, annotationColumn = 6 )
    
    # --- Generate a distance matrix ---
    message("Generating distance matrix...")
    distmat <- distanceMatrix (annolist, mz_tolerance = 3e-5 )
    
    # Save processed data objects and tables
    message("Saving output data and tables...")
    saveRDS(annolist, "annotated_spectra_list.rds")
    saveRDS(distmat, "distance_matrix.rds")
    readr::write_csv(fl_annos, "feature_list_annotations.csv")
    
    # --- Visualize similarities and plot individual annotated ---
    message("Generating visualization plots...")
    pdf("clumsid_plots.pdf", width = 10, height = 10)
    
    # Hierarchical clustering plot
    tryCatch({
      HCplot (distmat, h = 0.7 , cex = 0.7 )
    }, error = function(e) {
      message("Error generating HCplot: ", e\$message)
    })
    
    # Plot individual spectra
    tryCatch({
      specplot ( getSpectrum (annolist, "annotation" , "Stearic acid" ))
    }, error = function(e) {
      message("Could not plot Stearic acid spectrum: ", e\$message)
    })
    
    tryCatch({
      specplot ( getSpectrum (annolist, "annotation" , "Arachidic acid" ))
    }, error = function(e) {
      message("Could not plot Arachidic acid spectrum: ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'annotated_spectra_list.rds', 'distance_matrix.rds', 'feature_list_annotations.csv', and 'clumsid_plots.pdf'.")

    writeLines(c(
        '"BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS":',
        paste0('        clumsid: ', as.character(packageVersion("clumsid")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms2_multi_file_external_peaks.csv versions.yml
    """
}

workflow BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ YH1_GA7_01_10463.mzML, AX1_GB5_01_10470.mzML, LP1_GB3_01_10467.mzML, BR1_GB6_01_10471.mzML, m_mtbls433_metabolite_profiling_mass_spectrometry_v2_maf.tsv ] ]

    main:
    BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS(ch_input)

    emit:
    tables   = BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS.out.tables
    plots    = BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS.out.plots
    objects  = BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS.out.objects
    versions = BIOC_CLUMSID_LC_MS2_MULTI_FILE_EXTERNAL_PEAKS.out.versions
}
