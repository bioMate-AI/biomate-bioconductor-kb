#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mBPCR — direct_vector_profile_estimation
// Perform piecewise constant regression directly on raw numeric vectors of copy number values and physical positions.
// Input: jekoChr11Array250Knsp
// Container: quay.io/biocontainers/bioconductor-mbpcr:1.64.0--r45hdfd78af_0
// Requires: mBPCR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract raw log2 ratio and physical position vectors
//  * 2. [Core Analysis] Compute the mBPCR profile directly using computeMBPCR
//  * 3. [Visualization & Output] Plot the raw data alongside the estimated mBPCR and BRC curves

nextflow.enable.dsl = 2

process BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load required library
        library(mBPCR)
        
        # 1. Read the user input file 'jekoChr11Array250Knsp' from the working directory
        # We handle multiple possible formats (RDS, TSV, CSV) for robustness.
        jekoChr11Array250Knsp <- NULL
        
        if (file.exists("jekoChr11Array250Knsp.rds")) {
          jekoChr11Array250Knsp <- readRDS("jekoChr11Array250Knsp.rds")
        } else if (file.exists("jekoChr11Array250Knsp")) {
          jekoChr11Array250Knsp <- tryCatch({
            readRDS("jekoChr11Array250Knsp")
          }, error = function(e) {
            tryCatch({
              read.table("jekoChr11Array250Knsp", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
            }, error = function(e2) {
              read.csv("jekoChr11Array250Knsp", stringsAsFactors = FALSE)
            })
          })
        } else if (file.exists("jekoChr11Array250Knsp.csv")) {
          jekoChr11Array250Knsp <- read.csv("jekoChr11Array250Knsp.csv", stringsAsFactors = FALSE)
        } else if (file.exists("jekoChr11Array250Knsp.txt")) {
          jekoChr11Array250Knsp <- read.table("jekoChr11Array250Knsp.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        } else {
          stop("Required input file 'jekoChr11Array250Knsp' (or with .rds/.csv/.txt extension) not found in the working directory.")
        }
        
        # 2. Extract raw log2 ratio and physical position vectors
        y <- jekoChr11Array250Knsp\$log2ratio
        p <- jekoChr11Array250Knsp\$PhysicalPosition
        
        # 3. Compute the mBPCR profile directly using computeMBPCR
        # Estimate global parameters dynamically from the user's data
        globParam <- estGlobParam(y)
        results <- computeMBPCR(y, nu=globParam\$nu, rhoSquare=globParam\$rhoSquare, sigmaSquare=globParam\$sigmaSquare, regr='BRC')
        
        # 4. Plot the raw data alongside the estimated mBPCR and BRC curves and save to PDF
        pdf("mBPCR_profile_plot.pdf", width = 8, height = 6)
        plot(p,y)
        points(p, results\$estPC, type='l', col='red')
        points(p, results\$regrCurve, type='l', col='green')
        legend(x='bottomleft', legend=c('mBPCR', 'BRC with K_2'), lty=c(1, 1), col=c(4, 2))
        dev.off()
        
        # 5. Write named output files for the meaningful results
        # Save the results object as RDS
        saveRDS(results, file = "mBPCR_results.rds")
        
        # Save the estimated profile as a CSV table
        output_df <- data.frame(
          PhysicalPosition = p,
          RawLog2Ratio = y,
          mBPCR_estPC = results\$estPC,
          BRC_regrCurve = results\$regrCurve
        )
        write.csv(output_df, file = "mBPCR_estimated_profile.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION":',
        paste0('    mBPCR: ', as.character(packageVersion('mBPCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_vector_profile_estimation.csv versions.yml
    """
}

workflow BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ jekoChr11Array250Knsp ] ]

    main:
    BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION.out.tables
    plots    = BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION.out.plots
    objects  = BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION.out.objects
    versions = BIOC_MBPCR_DIRECT_VECTOR_PROFILE_ESTIMATION.out.versions
}
