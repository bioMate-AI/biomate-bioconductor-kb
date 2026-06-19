#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mbpcr — direct_mbpcr_computation
// Directly estimate the profile of a specific chromosome subregion or simulated vector without whole-genome overhead.
// Input: jekoChr11Array250Knsp
// Container: quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0
// R packages: mBPCR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0"

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
    .bm_deps <- c("mBPCR")
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
    
    # Load required library
    library(mBPCR)
    
    # Robustly load the user-provided dataset 'jekoChr11Array250Knsp' from the working directory
    jekoChr11Array250Knsp <- NULL
    possible_files <- c(
      "jekoChr11Array250Knsp",
      "jekoChr11Array250Knsp.rds",
      "jekoChr11Array250Knsp.RData",
      "jekoChr11Array250Knsp.csv",
      "jekoChr11Array250Knsp.txt"
    )
    
    for (f in possible_files) {
      if (file.exists(f)) {
        # Try RDS
        try_rds <- tryCatch(readRDS(f), error = function(e) NULL)
        if (!is.null(try_rds)) {
          jekoChr11Array250Knsp <- try_rds
          break
        }
        # Try RData
        env <- new.env()
        try_rdata <- tryCatch({
          load(f, envir = env)
          env[[ls(env)[1]]]
        }, error = function(e) NULL)
        if (!is.null(try_rdata)) {
          jekoChr11Array250Knsp <- try_rdata
          break
        }
        # Try CSV
        try_csv <- tryCatch(read.csv(f, header = TRUE), error = function(e) NULL)
        if (!is.null(try_csv) && "log2ratio" %in% colnames(try_csv)) {
          jekoChr11Array250Knsp <- try_csv
          break
        }
        # Try TSV
        try_tsv <- tryCatch(read.table(f, header = TRUE, sep = "\t"), error = function(e) NULL)
        if (!is.null(try_tsv) && "log2ratio" %in% colnames(try_tsv)) {
          jekoChr11Array250Knsp <- try_tsv
          break
        }
      }
    }
    
    if (is.null(jekoChr11Array250Knsp)) {
      stop("Error: Could not load 'jekoChr11Array250Knsp' from the working directory.")
    }
    
    # --- Extract the copy number vector y and position vector p ---
    y <- jekoChr11Array250Knsp\$log2ratio[10600:11200]
    p <- jekoChr11Array250Knsp\$PhysicalPosition[10600:11200]
    
    # --- Compute the profile directly using computeMBPCR ---
    results <- computeMBPCR(y, nu=-3.012772e-10, rhoSquare=0.0479, sigmaSquare=0.0699, regr='BRC')
    
    # --- Plot the raw data and the estimated curves to a PDF file ---
    pdf("direct_mbpcr_profile.pdf", width = 8, height = 6)
    plot(p, y)
    points(p, results\$estPC, type='l', col='red')
    points(p, results\$regrCurve, type='l', col='green')
    legend(x='bottomleft', legend=c('mBPCR', 'BRC with K_2'), lty=c(1, 1), col=c(4, 2))
    dev.off()
    
    # --- Write named output files for the meaningful results ---
    # Save the full results object as an RDS file
    saveRDS(results, file = "mbpcr_results.rds")
    
    # Save the estimated profile and regression curve as a CSV table
    results_df <- data.frame(
      PhysicalPosition = p,
      RawLog2Ratio = y,
      estPC = results\$estPC,
      regrCurve = results\$regrCurve
    )
    write.csv(results_df, file = "mbpcr_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION":',
        paste0('        mbpcr: ', as.character(packageVersion("mbpcr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_mbpcr_computation.csv versions.yml
    """
}

workflow BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ jekoChr11Array250Knsp ] ]

    main:
    BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION(ch_input)

    emit:
    tables   = BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION.out.tables
    plots    = BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION.out.plots
    objects  = BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION.out.objects
    versions = BIOC_MBPCR_DIRECT_MBPCR_COMPUTATION.out.versions
}
