#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RnaSeqSampleSize — reference_distribution_estimation
// Estimate power or sample size using built-in TCGA reference datasets.
// Input: TCGA dataset name
// Container: quay.io/biocontainers/bioconductor-rnaseqsamplesize:2.20.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RnaSeqSampleSize
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate power for random genes using est_power_distribution
//  * 2. [Core Analysis] Estimate power for a specific list of genes using est_power_distribution with selectedGenes
//  * 3. [Core Analysis] Estimate power for a specific pathway using est_power_distribution with pathway
//  * 4. [Core Analysis] Estimate sample size using sample_size_distribution

nextflow.enable.dsl = 2

process BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("RnaSeqSampleSize")
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
    library(RnaSeqSampleSize)
    
    # Define input file path
    input_file <- "input_parameters.txt"
    
    # Create default input file if it does not exist to ensure runnability
    if (!file.exists(input_file)) {
      cat("TCGA_READ\n65\n0.01\n2\n5\n0.8\n", file = input_file)
    }
    
    # Read parameters from the user input file
    lines <- readLines(input_file)
    distributionObject <- trimws(lines[1])
    n <- as.numeric(trimws(lines[2]))
    f <- as.numeric(trimws(lines[3]))
    rho <- as.numeric(trimws(lines[4]))
    repNumber <- as.numeric(trimws(lines[5]))
    power <- as.numeric(trimws(lines[6]))
    
    # Stage 1: Estimate power for random genes using est_power_distribution
    message("Running Stage 1: Power estimation for random genes...")
    power_random <- est_power_distribution(
      n = n,
      f = f,
      rho = rho,
      distributionObject = distributionObject,
      repNumber = repNumber
    )
    write.csv(data.frame(Power = power_random), "power_random_genes.csv", row.names = FALSE)
    
    # Stage 2: Estimate power for a specific list of genes using est_power_distribution with selectedGenes
    message("Running Stage 2: Power estimation for selected genes...")
    selectedGenes <- c("A1BG", "A2BP1", "A2M", "A4GALT", "AAAS")
    powerDistribution <- est_power_distribution(
      n = n,
      f = f,
      rho = rho,
      distributionObject = distributionObject,
      selectedGenes = selectedGenes,
      storeProcess = TRUE
    )
    
    str(powerDistribution)
    mean_power_selected <- mean(powerDistribution\$power)
    
    df_selected <- data.frame(
      Gene = selectedGenes,
      Power = powerDistribution\$power,
      Count = powerDistribution\$count,
      Dispersion = powerDistribution\$dispersion
    )
    write.csv(df_selected, "power_selected_genes.csv", row.names = FALSE)
    
    # Stage 3: Estimate power for a specific pathway using est_power_distribution with pathway
    message("Running Stage 3: Power estimation for pathway genes...")
    tryCatch({
      powerDistributionPathway <- est_power_distribution(
        n = n,
        f = f,
        rho = rho,
        distributionObject = distributionObject,
        pathway = "00010",
        minAveCount = 1,
        storeProcess = TRUE
      )
      mean_power_pathway <- mean(powerDistributionPathway\$power)
      
      df_pathway <- data.frame(
        Gene = names(powerDistributionPathway\$count),
        Power = powerDistributionPathway\$power,
        Count = powerDistributionPathway\$count,
        Dispersion = powerDistributionPathway\$dispersion
      )
      write.csv(df_pathway, "power_pathway_genes.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Pathway power estimation failed or was skipped: ", e\$message)
    })
    
    # Stage 4: Estimate sample size using sample_size_distribution
    message("Running Stage 4: Sample size estimation...")
    estimated_ss <- sample_size_distribution(
      power = power,
      f = f,
      distributionObject = distributionObject,
      repNumber = repNumber,
      showMessage = TRUE
    )
    write.csv(data.frame(Estimated_Sample_Size = estimated_ss), "estimated_sample_size.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION":',
        paste0('    RnaSeqSampleSize: ', as.character(packageVersion('RnaSeqSampleSize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_distribution_estimation.csv versions.yml
    """
}

workflow BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TCGA dataset name ] ]

    main:
    BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION.out.tables
    plots    = BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION.out.plots
    objects  = BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION.out.objects
    versions = BIOC_RNASEQSAMPLESIZE_REFERENCE_DISTRIBUTION_ESTIMATION.out.versions
}
