#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RnaSeqSampleSize — visualization_and_optimization
// Generate power curves for different FDR thresholds and optimize parameters (sample size vs. read depth).
// Input: User-defined numeric parameters and ranges.
// Container: quay.io/biocontainers/bioconductor-rnaseqsamplesize:2.20.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RnaSeqSampleSize
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate power curves using est_power_curve
//  * 2. [Visualization & Output] Plot power curves using plot_power_curve
//  * 3. [Core Analysis] Optimize parameters using optimize_parameter

nextflow.enable.dsl = 2

process BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION {
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
    
    # Define the input file name
    input_file <- "parameters.csv"
    
    # Create a default parameters.csv if it does not exist to ensure runnability
    if (!file.exists(input_file)) {
      default_params <- data.frame(
        parameter = c("n", "f1", "f2", "rho", "lambda0", "phi0", "opt1Value", "opt2Value"),
        value = c("63", "0.01", "0.05", "2", "5", "0.5", "3;5;10;15;20", "1;2;3;4;5;10;20"),
        stringsAsFactors = FALSE
      )
      write.csv(default_params, input_file, row.names = FALSE)
    }
    
    # Read user-defined parameters from the CSV file
    params <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Parse parameters
    n <- as.numeric(params\$value[params\$parameter == "n"])
    f1 <- as.numeric(params\$value[params\$parameter == "f1"])
    f2 <- as.numeric(params\$value[params\$parameter == "f2"])
    rho <- as.numeric(params\$value[params\$parameter == "rho"])
    lambda0 <- as.numeric(params\$value[params\$parameter == "lambda0"])
    phi0 <- as.numeric(params\$value[params\$parameter == "phi0"])
    
    opt1Value_raw <- params\$value[params\$parameter == "opt1Value"]
    opt1Value <- as.numeric(unlist(strsplit(opt1Value_raw, ";")))
    
    opt2Value_raw <- params\$value[params\$parameter == "opt2Value"]
    opt2Value <- as.numeric(unlist(strsplit(opt2Value_raw, ";")))
    
    # Stage 1: Generate power curves using est_power_curve
    result1 <- est_power_curve(n = n, f = f1, rho = rho, lambda0 = lambda0, phi0 = phi0)
    result2 <- est_power_curve(n = n, f = f2, rho = rho, lambda0 = lambda0, phi0 = phi0)
    
    # Save power curve data objects
    saveRDS(result1, "power_curve_f1.rds")
    saveRDS(result2, "power_curve_f2.rds")
    
    # Stage 2: Plot power curves using plot_power_curve
    pdf("power_curves_plot.pdf", width = 7, height = 6)
    plot_power_curve(list(result1, result2))
    dev.off()
    
    # Stage 3: Optimize parameters using optimize_parameter
    pdf("optimization_plot.pdf", width = 7, height = 6)
    result <- optimize_parameter(
      fun = est_power,
      opt1 = "n",
      opt2 = "lambda0",
      opt1Value = opt1Value,
      opt2Value = opt2Value
    )
    dev.off()
    
    # Save optimization matrix result
    write.csv(result, "optimization_matrix.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION":',
        paste0('    RnaSeqSampleSize: ', as.character(packageVersion('RnaSeqSampleSize')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visualization_and_optimization.csv versions.yml
    """
}

workflow BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ User-defined numeric parameters and ranges. ] ]

    main:
    BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION.out.tables
    plots    = BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION.out.plots
    objects  = BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION.out.objects
    versions = BIOC_RNASEQSAMPLESIZE_VISUALIZATION_AND_OPTIMIZATION.out.versions
}
