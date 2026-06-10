#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seahtrue — seahorse_xf_preprocessing
// Read, preprocess, and validate Seahorse XF analyzer Excel data into structured nested tibbles.
// Input: 20191219_SciRep_PBMCs_donor_A.xlsx
// Container: quay.io/biocontainers/bioconductor-seahtrue:1.4.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seahtrue:1.4.0--r45hdfd78af_0"

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
    .bm_deps <- c("dplyr", "ggplot2", "purrr", "readr", "seahtrue", "stringr", "tidyverse")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(dplyr)
    library(seahtrue)
    library(purrr)
    library(stringr)
    library(readr)
    
    # Define input file path (must exist in the working directory)
    input_file <- "20191219_SciRep_PBMCs_donor_A.xlsx"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file not found in the working directory:", input_file))
    }
    
    # 1. Read and preprocess the Seahorse plate data using revive_xfplate()
    # Adapted from the documented code to read directly from the local file
    revive_output_donor_A <- 
      input_file %>% 
      seahtrue::revive_xfplate()
    
    # 2. Inspect the structure of the nested tibble
    revive_output_donor_A %>%  
      dplyr::glimpse()
    
    # 3. Extract rate data, raw data, assay information, and injection information using purrr::pluck()
    # Extract Rate Data
    rate_data <- revive_output_donor_A %>%  
      purrr::pluck("rate_data", 1)
    
    print("Rate Data:")
    print(rate_data)
    
    # Extract Raw Data
    raw_data <- revive_output_donor_A %>%  
      purrr::pluck("raw_data", 1)
    
    print("Raw Data:")
    print(raw_data)
    
    # Extract Assay Info and Cartridge Barcode
    cartridge_barcode <- revive_output_donor_A %>%  
      purrr::pluck("assay_info", 1) %>% 
      pull(cartridge_barcode)
    
    print(paste("Cartridge Barcode:", cartridge_barcode))
    
    # KSV in barcode
    ksv_barcode <- revive_output_donor_A %>%  
      purrr::pluck("assay_info", 1) %>% 
      pull(cartridge_barcode) %>% 
      stringr::str_sub(-18, -13)
    
    print(paste("KSV in barcode:", ksv_barcode))
      
    # KSV in assay info sheet
    ksv_assay <- revive_output_donor_A %>%  
      purrr::pluck("assay_info", 1) %>% 
      pull(KSV) 
    
    print(paste("KSV in assay info:", ksv_assay))
    
    # F0 from assay info sheet
    f0_assay <- revive_output_donor_A %>%  
      purrr::pluck("assay_info", 1) %>% 
      pull(F0) 
    
    print(paste("F0 from assay info:", f0_assay))
    
    # Minutes to start measurement one
    minutes_to_start <- revive_output_donor_A %>%  
      purrr::pluck("assay_info", 1) %>% 
      pull(minutes_to_start_measurement_one)
    
    print(paste("Minutes to start measurement one:", minutes_to_start))
    
    # Inspect rate data structure and attributes
    revive_output_donor_A %>%  
      purrr::pluck("rate_data", 1) %>% 
      str()
    
    # Check background correction status attribute
    was_bg_corrected <- revive_output_donor_A %>%  
      purrr::pluck("rate_data", 1) %>% 
      attributes() %>% 
      purrr::pluck("was_background_corrected")
    
    print(paste("Was background corrected:", was_bg_corrected))
    
    # Extract Injection Info
    injection_info <- revive_output_donor_A %>%  
      purrr::pluck("injection_info", 1)
    
    print("Injection Info:")
    print(injection_info)
    
    # 4. Write named output files for the meaningful results
    message("Saving processed outputs to disk...")
    
    # Save the complete nested tibble as an RDS object
    saveRDS(revive_output_donor_A, "revive_output_donor_A.rds")
    
    # Save individual extracted tables as CSV files
    readr::write_csv(rate_data, "rate_data.csv")
    readr::write_csv(raw_data, "raw_data.csv")
    readr::write_csv(revive_output_donor_A %>% purrr::pluck("assay_info", 1), "assay_info.csv")
    readr::write_csv(injection_info, "injection_info.csv")
    
    message("Pipeline completed successfully. Outputs saved: 'revive_output_donor_A.rds', 'rate_data.csv', 'raw_data.csv', 'assay_info.csv', 'injection_info.csv'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING":
        seahtrue: \$(Rscript -e 'cat(as.character(packageVersion("seahtrue")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seahorse_xf_preprocessing.csv versions.yml
    """
}

workflow BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ 20191219_SciRep_PBMCs_donor_A.xlsx ] ]

    main:
    BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING.out.tables
    plots    = BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING.out.plots
    objects  = BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING.out.objects
    versions = BIOC_SEAHTRUE_SEAHORSE_XF_PREPROCESSING.out.versions
}
