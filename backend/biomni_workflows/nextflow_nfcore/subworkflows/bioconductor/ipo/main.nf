#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ipo — xcms_parameter_optimization
// Optimize XCMS peak picking, retention time correction, and grouping parameters using Design of Experiments (DoE) and generate an optimized processing script.
// Input: datafiles
// Container: quay.io/biocontainers/bioconductor-ipo:1.36.0--r45hdfd78af_0
// R packages: faahKO, IPO
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ipo:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("faahKO", "IPO")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(IPO)
    
    # 1. Locate user input files in the working directory
    # Supporting common mass spectrometry formats: CDF, mzML, mzXML, raw
    datafiles <- list.files(
      path = ".",
      pattern = "\\\\.(cdf|mzml|mzxml|raw)\$",
      ignore.case = TRUE,
      full.names = TRUE,
      recursive = TRUE
    )
    
    if (length(datafiles) < 2) {
      stop("Error: At least 2 raw mass spectrometry files (CDF, mzML, mzXML, or raw) are required in the working directory for IPO optimization.")
    }
    
    # 2. Define starting parameters for peak picking
    peakpickingParameters <- getDefaultXcmsSetStartingParams('matchedFilter')
    # setting levels for step to 0.2 and 0.3 (hence 0.25 is the center point)
    peakpickingParameters\$step <- c(0.2, 0.3)
    peakpickingParameters\$fwhm <- c(40, 50)
    # setting only one value for steps therefore this parameter is not optimized
    peakpickingParameters\$steps <- 2
    
    # Open PDF device to capture response surface plots
    pdf("ipo_optimization_plots.pdf", width = 8, height = 8)
    
    # 3. Optimize peak picking parameters
    time.xcmsSet <- system.time({ # measuring time
    resultPeakpicking <- 
      optimizeXcmsSet(files = datafiles[1:2], 
                      params = peakpickingParameters, 
                      nSlaves = 1, 
                      subdir = NULL,
                      plot = TRUE)
    })
    
    # Extract best settings and optimized xcmsSet object
    best_peakpicking_result <- resultPeakpicking\$best_settings\$result
    optimizedXcmsSetObject <- resultPeakpicking\$best_settings\$xset
    
    # 4. Define starting parameters for retention time correction and grouping
    retcorGroupParameters <- getDefaultRetGroupStartingParams()
    retcorGroupParameters\$profStep <- 1
    retcorGroupParameters\$gapExtend <- 2.7
    
    # 5. Optimize retention time correction and grouping parameters simultaneously
    time.RetGroup <- system.time({ # measuring time
    resultRetcorGroup <-
      optimizeRetGroup(xset = optimizedXcmsSetObject, 
                       params = retcorGroupParameters, 
                       nSlaves = 1, 
                       subdir = NULL,
                       plot = TRUE)
    })
    
    # Close PDF device
    dev.off()
    
    # 6. Save meaningful results to files
    # Save RDS objects for downstream analysis
    saveRDS(resultPeakpicking, "result_peakpicking.rds")
    saveRDS(resultRetcorGroup, "result_retcor_group.rds")
    saveRDS(optimizedXcmsSetObject, "optimized_xcms_set.rds")
    
    # Save best peak picking results table
    write.csv(best_peakpicking_result, "best_peakpicking_result.csv", row.names = FALSE)
    
    # Save best retention time correction and grouping parameters
    best_retgroup_parameters <- resultRetcorGroup\$best_settings
    saveRDS(best_retgroup_parameters, "best_retgroup_parameters.rds")
    
    # 7. Generate and save the optimized R processing script
    sink("optimized_xcms_processing_script.R")
    writeRScript(resultPeakpicking\$best_settings\$parameters, 
                 resultRetcorGroup\$best_settings)
    sink()
    
    # Print execution summary
    cat("\n--- IPO Optimization Summary ---\n")
    cat("Peak picking optimization time (seconds):\n")
    print(time.xcmsSet)
    cat("\nRetention time correction & grouping optimization time (seconds):\n")
    print(time.RetGroup)
    cat("\nOptimized parameters script saved to 'optimized_xcms_processing_script.R'\n")
    cat("Plots saved to 'ipo_optimization_plots.pdf'\n")

    writeLines(c(
        '"BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION":',
        paste0('        ipo: ', as.character(packageVersion("ipo")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xcms_parameter_optimization.csv versions.yml
    """
}

workflow BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datafiles ] ]

    main:
    BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION.out.tables
    plots    = BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION.out.plots
    objects  = BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION.out.objects
    versions = BIOC_IPO_XCMS_PARAMETER_OPTIMIZATION.out.versions
}
