#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FitHiC — fithic_hicpro_analysis
// Run Fit-Hi-C on HiC-Pro pipeline outputs incorporating ICE bias values.
// Input: data_5000000_abs.bed.gz, data_5000000.matrix.gz, data_5000000_iced.matrix.biases.gz
// Container: quay.io/biocontainers/bioconductor-fithic:1.36.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: FitHiC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define paths to HiC-Pro input files and output directory
//  * 2. [Core Analysis] Run the FitHiC function with useHiCPro=TRUE and the bias file specified

nextflow.enable.dsl = 2

process BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS {
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
    
    # Load the required library
    library("FitHiC")
    
    # Define paths to the user input files in the working directory
    fragsfile <- "data_5000000_abs.bed.gz"
    intersfile <- "data_5000000.matrix.gz"
    biasfile <- "data_5000000_iced.matrix.biases.gz"
    
    # Define the output directory
    outdir <- file.path(getwd(), "data_5000000")
    if (!dir.exists(outdir)) {
      dir.create(outdir, recursive = TRUE)
    }
    
    # Run Fit-Hi-C with the specified parameters and ICE bias file
    FitHiC(fragsfile, intersfile, outdir, biasfile, libname="data_5000000",
        distUpThres=500000000, distLowThres=5000000, visual=TRUE, useHiCPro=TRUE)
    
    # Export meaningful results to standard formats (CSV and RDS)
    pass1_sig_file <- file.path(outdir, "data_5000000.spline_pass1.significances.txt.gz")
    pass2_sig_file <- file.path(outdir, "data_5000000.spline_pass2.significances.txt.gz")
    
    if (file.exists(pass1_sig_file)) {
      pass1_data <- read.table(gzfile(pass1_sig_file), header = TRUE)
      write.csv(pass1_data, file = "fithic_results_pass1.csv", row.names = FALSE)
      saveRDS(pass1_data, file = "fithic_results_pass1.rds")
    }
    
    if (file.exists(pass2_sig_file)) {
      pass2_data <- read.table(gzfile(pass2_sig_file), header = TRUE)
      write.csv(pass2_data, file = "fithic_results_pass2.csv", row.names = FALSE)
      saveRDS(pass2_data, file = "fithic_results_pass2.rds")
    }

    writeLines(c(
        '"BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS":',
        paste0('    FitHiC: ', as.character(packageVersion('FitHiC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fithic_hicpro_analysis.csv versions.yml
    """
}

workflow BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_5000000_abs.bed.gz, data_5000000.matrix.gz, data_5000000_iced.matrix.biases.gz ] ]

    main:
    BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS.out.tables
    plots    = BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS.out.plots
    objects  = BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS.out.objects
    versions = BIOC_FITHIC_FITHIC_HICPRO_ANALYSIS.out.versions
}
