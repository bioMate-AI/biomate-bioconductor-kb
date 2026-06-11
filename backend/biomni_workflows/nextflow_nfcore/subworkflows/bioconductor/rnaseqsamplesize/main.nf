#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RnaSeqSampleSize — single_parameter_estimation
// Estimate power or sample size using single user-defined values for read count and dispersion.
// Input: User-defined numeric parameters
// Container: quay.io/biocontainers/bioconductor-rnaseqsamplesize:2.20.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RnaSeqSampleSize
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate power using est_power
//  * 2. [Core Analysis] Estimate sample size using sample_size

nextflow.enable.dsl = 2

process BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    
    # Load the required Bioconductor package
    library(RnaSeqSampleSize)
    
    # Define default user-defined numeric parameters
    n <- 63
    rho <- 2
    lambda0 <- 5
    phi0 <- 0.5
    f <- 0.01
    power <- 0.8
    
    # If a parameters.csv file exists in the working directory, read from it
    if (file.exists("parameters.csv")) {
      params <- read.csv("parameters.csv", stringsAsFactors = FALSE)
      if ("n" %in% params\$parameter) {
        n <- as.numeric(params\$value[params\$parameter == "n"])
      }
      if ("rho" %in% params\$parameter) {
        rho <- as.numeric(params\$value[params\$parameter == "rho"])
      }
      if ("lambda0" %in% params\$parameter) {
        lambda0 <- as.numeric(params\$value[params\$parameter == "lambda0"])
      }
      if ("phi0" %in% params\$parameter) {
        phi0 <- as.numeric(params\$value[params\$parameter == "phi0"])
      }
      if ("f" %in% params\$parameter) {
        f <- as.numeric(params\$value[params\$parameter == "f"])
      }
      if ("power" %in% params\$parameter) {
        power <- as.numeric(params\$value[params\$parameter == "power"])
      }
    }
    
    # Stage 1: Estimate power using est_power
    estimated_power <- est_power(n=n, rho=rho, lambda0=lambda0, phi0=phi0, f=f)
    
    # Stage 2: Estimate sample size using sample_size
    estimated_sample_size <- sample_size(power=power, f=f, rho=rho, lambda0=lambda0, phi0=phi0)
    
    # Construct a summary table of the results
    results_df <- data.frame(
      Analysis = c("Power Estimation", "Sample Size Estimation"),
      Input_n = c(n, NA),
      Input_Target_Power = c(NA, power),
      Fold_Change_Rho = c(rho, rho),
      Min_Average_Read_Count_Lambda0 = c(lambda0, lambda0),
      Max_Dispersion_Phi0 = c(phi0, phi0),
      FDR_f = c(f, f),
      Result_Power = c(estimated_power, NA),
      Result_Sample_Size = c(NA, estimated_sample_size),
      stringsAsFactors = FALSE
    )
    
    # Write outputs to the working directory
    write.csv(results_df, "rna_seq_sample_size_estimation_results.csv", row.names = FALSE)
    
    saveRDS(
      list(
        power_estimation = estimated_power,
        sample_size_estimation = estimated_sample_size,
        parameters = list(n = n, rho = rho, lambda0 = lambda0, phi0 = phi0, f = f, power = power)
      ),
      file = "rna_seq_sample_size_estimation_results.rds"
    )

    writeLines(c(
        '"BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION":',
        paste0('    RnaSeqSampleSize: ', as.character(packageVersion('RnaSeqSampleSize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_parameter_estimation.csv versions.yml
    """
}

workflow BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ User-defined numeric parameters ] ]

    main:
    BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION.out.tables
    plots    = BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION.out.plots
    objects  = BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION.out.objects
    versions = BIOC_RNASEQSAMPLESIZE_SINGLE_PARAMETER_ESTIMATION.out.versions
}
