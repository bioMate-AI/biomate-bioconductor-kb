#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TurboNorm — scatterplot_smoothing
// Fit a fast piecewise constant P-spline to scatterplot data to estimate the underlying trend.
// Input: x.txt, y.txt
// Container: quay.io/biocontainers/bioconductor-turbonorm:1.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TurboNorm
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the TurboNorm library
//  * 2. [Core Analysis] Fit the trend using turbotrend()
//  * 3. [Core Analysis] Inspect the fitted model object

nextflow.enable.dsl = 2

process BIOC_TURBONORM_SCATTERPLOT_SMOOTHING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    
    # 1. Load the TurboNorm library
    library(TurboNorm)
    
    # 2. Read the user input files
    if (!file.exists("x.txt") || !file.exists("y.txt")) {
      stop("Input files x.txt and/or y.txt not found in the working directory.")
    }
    
    x <- scan("x.txt", quiet = TRUE)
    y <- scan("y.txt", quiet = TRUE)
    
    # 3. Fit the trend using turbotrend() exactly as documented
    fitOrig <- turbotrend(x, y, n=15, method="original")
    
    # 4. Inspect the fitted model object and save the console output
    sink("fit_summary.txt")
    print(fitOrig)
    sink()
    
    # Save the fitted model object as an RDS file
    saveRDS(fitOrig, "fitOrig.rds")
    
    # 5. Plot the results and save to a PDF file
    pdf("turbotrend_plot.pdf")
    plot(x, y, type='p', xlab="", ylab="")
    lines(fitOrig, col="green", type='b', pch=1)
    dev.off()

    writeLines(c(
        '"BIOC_TURBONORM_SCATTERPLOT_SMOOTHING":',
        paste0('    TurboNorm: ', as.character(packageVersion('TurboNorm')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scatterplot_smoothing.csv versions.yml
    """
}

workflow BIOC_TURBONORM_SCATTERPLOT_SMOOTHING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ x.txt, y.txt ] ]

    main:
    BIOC_TURBONORM_SCATTERPLOT_SMOOTHING(ch_input)

    emit:
    tables   = BIOC_TURBONORM_SCATTERPLOT_SMOOTHING.out.tables
    plots    = BIOC_TURBONORM_SCATTERPLOT_SMOOTHING.out.plots
    objects  = BIOC_TURBONORM_SCATTERPLOT_SMOOTHING.out.objects
    versions = BIOC_TURBONORM_SCATTERPLOT_SMOOTHING.out.versions
}
