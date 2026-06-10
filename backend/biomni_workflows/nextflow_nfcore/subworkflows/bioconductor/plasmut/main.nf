#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: plasmut — plasmut_origin_quantification
// Quantify the likelihood of plasma mutations originating from tumor vs. clonal hematopoiesis using matched plasma and buffy coat sequencing data.
// Input: user_mutation_data.csv
// Container: quay.io/biocontainers/bioconductor-plasmut:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: magrittr, plasmut, tidyverse
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format the input mutation data into a nested tibble grouped by a unique mutation identifier (uid)
//  * 2. [Input & Preparation] Define the prior parameters and Monte Carlo settings in a parameter list
//  * 3. [Core Analysis] Run the importance sampler using importance_sampler() to calculate marginal likelihoods and Bayes factors
//  * 4. [Core Analysis] Extract and interpret the log Bayes factors

nextflow.enable.dsl = 2

process BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(magrittr)
    library(tidyverse)
    library(plasmut)
    
    # Define input file path
    input_file <- "user_mutation_data.csv"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read and standardize the user input mutation data
    raw_data <- read_csv(input_file, show_col_types = FALSE)
    
    # Map user columns to the expected format: patient, gene, aa, analyte, y, n, position
    crcseq <- raw_data %>%
      rename_with(~ case_when(
        .x %in% c("patient", "patient_id", "sample_id", "sample/patient ID", "sample") ~ "patient",
        .x %in% c("gene", "mutation", "gene/mutation") ~ "gene",
        .x %in% c("analyte", "analyte type", "analyte_type") ~ "analyte",
        .x %in% c("y", "mutant read count", "mutant_reads", "mutant_count") ~ "y",
        .x %in% c("n", "total read count", "total_reads", "total_count") ~ "n",
        .x %in% c("aa", "amino_acid", "protein_change") ~ "aa",
        .x %in% c("position", "pos") ~ "position",
        TRUE ~ .x
      ))
    
    # Ensure required columns exist
    required_cols <- c("patient", "gene", "analyte", "y", "n")
    missing_cols <- setdiff(required_cols, colnames(crcseq))
    if (length(missing_cols) > 0) {
      stop(paste("Missing required column(s):", paste(missing_cols, collapse = ", ")))
    }
    
    # Add optional columns if missing to prevent downstream failures
    if (!"aa" %in% colnames(crcseq)) {
      crcseq <- crcseq %>% mutate(aa = "unknown")
    }
    if (!"position" %in% colnames(crcseq)) {
      crcseq <- crcseq %>% mutate(position = 1)
    }
    
    # Enforce correct data types
    crcseq <- crcseq %>%
      mutate(
        patient = as.character(patient),
        gene = as.character(gene),
        aa = as.character(aa),
        analyte = as.character(analyte),
        y = as.integer(y),
        n = as.integer(n),
        position = as.integer(position)
      )
    
    # Define prior parameters and Monte Carlo settings
    params <- list(ctdna = list(a = 1, b = 9), 
                   ctc = list(a = 1, b = 10^3), 
                   chip = list(a= 1, b = 9), 
                   montecarlo.samples = 50e3, 
                   prior.weight = 0.1)
    
    # Format the input mutation data into a nested tibble grouped by a unique mutation identifier (uid)
    muts <- unite(crcseq, "uid", c(patient, gene), remove = FALSE) %>% 
            group_by(uid) %>% nest()
    
    # Run the importance sampler to calculate marginal likelihoods and Bayes factors
    muts\$IS <- muts\$data %>% map(importance_sampler, params)
    
    # Define extraction function exactly as documented
    fun <- function(x){
        result <- x\$data %>%
            select(-position) %>%
            mutate(bayes_factor = x\$IS\$bayesfactor\$bayesfactor)
        return(result)
    }
    
    # Apply extraction function and format results
    bf <- apply(muts, 1, fun) 
    
    final_results <- bf %>% do.call(rbind, .) %>%
        as_tibble() %>%
        select(patient, gene, aa, bayes_factor) %>%
        rename(log_bf=bayes_factor) %>%
        distinct()
    
    # Write outputs to the working directory
    write_csv(final_results, "bayes_factors_output.csv")
    saveRDS(muts, "importance_sampler_results.rds")
    
    message("Pipeline completed successfully. Outputs written to 'bayes_factors_output.csv' and 'importance_sampler_results.rds'.")

    writeLines(c(
        '"BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION":',
        paste0('    plasmut: ', as.character(packageVersion('plasmut')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plasmut_origin_quantification.csv versions.yml
    """
}

workflow BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_mutation_data.csv ] ]

    main:
    BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION.out.tables
    plots    = BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION.out.plots
    objects  = BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION.out.objects
    versions = BIOC_PLASMUT_PLASMUT_ORIGIN_QUANTIFICATION.out.versions
}
