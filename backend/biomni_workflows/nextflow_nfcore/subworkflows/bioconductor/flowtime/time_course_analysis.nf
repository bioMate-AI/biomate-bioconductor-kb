#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowTime — time_course_analysis
// Analyze time-lapse flow cytometry data by annotating, gating, and generating summary statistics per sample and time point.
// Input: .fcs files, .csv file
// Container: quay.io/biocontainers/bioconductor-flowtime:1.34.0--r45hdfd78af_0
// R packages: flowCore, flowTime, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowTime, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import FCS files using read.flowSet
//  * 2. [Input & Preparation] Load metadata annotation using read.csv
//  * 3. [Core Analysis] Annotate the flowSet using annotateFlowSet
//  * 4. [Input & Preparation] Load cytometer-specific gates using loadGates
//  * 5. [Visualization & Output] Gate and summarize the flowSet using summarizeFlow
//  * 6. [Visualization & Output] Plot the summarized time-course data using qplot

nextflow.enable.dsl = 2

process BIOC_FLOWTIME_TIME_COURSE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("flowCore", "flowTime", "ggplot2")
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
    library(flowCore)
    library(flowTime)
    library(ggplot2)
    
    # 1. Import FCS files using read.flowSet from the working directory
    fcs_files <- list.files(path = ".", pattern = "\\\\.fcs\$", ignore.case = TRUE)
    if (length(fcs_files) == 0) {
      stop("Error: No .fcs files found in the working directory.")
    }
    plate1 <- read.flowSet(path = ".", pattern = "\\\\.fcs\$", alter.names = TRUE)
    dat <- plate1
    
    # 2. Load metadata annotation using read.csv from the working directory
    csv_files <- list.files(path = ".", pattern = "\\\\.csv\$", ignore.case = TRUE)
    if (length(csv_files) == 0) {
      stop("Error: No .csv annotation file found in the working directory.")
    }
    annotation <- read.csv(csv_files[1])
    
    # 3. Annotate the flowSet using annotateFlowSet
    adat <- annotateFlowSet(dat, annotation)
    
    # 4. Load cytometer-specific gates using loadGates
    # Locate the package's extdata directory dynamically to avoid system.file
    gates_path <- file.path(find.package("flowTime"), "extdata")
    loadGates(gatesFile = "C6Gates.RData", path = gates_path)
    
    # 5. Gate and summarize the flowSet using summarizeFlow
    dat_sum <- summarizeFlow(adat, ploidy = "diploid", only = "singlets", channel = "FL1.A")
    
    # Save the summarized data and annotated flowSet
    write.csv(dat_sum, "dat_sum.csv", row.names = FALSE)
    saveRDS(adat, "adat.rds")
    
    # 6. Plot the summarized time-course data
    # Dynamically determine columns to avoid hardcoding 'time' and 'treatment'
    x_var <- if ("time" %in% colnames(dat_sum)) "time" else colnames(annotation)[2]
    if (is.na(x_var)) x_var <- colnames(annotation)[1]
    
    group_var <- if ("treatment" %in% colnames(annotation)) "treatment" else colnames(annotation)[ncol(annotation)]
    
    p <- ggplot(dat_sum, aes(x = .data[[x_var]], y = FL1.Amean, linetype = factor(.data[[group_var]]))) + 
      geom_line() + 
      xlab("Time post Auxin addition (min)") + 
      ylab("Reporter Fluorescence (AU)") + 
      scale_color_discrete(name = expression(paste("Auxin (", mu, "M)", sep = ""))) + 
      theme_classic(base_size = 14, base_family = "Arial")
    
    # Save the plot to a PDF file
    pdf("time_course_plot.pdf", width = 8, height = 6)
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_FLOWTIME_TIME_COURSE_ANALYSIS":',
        paste0('    flowTime: ', as.character(packageVersion('flowTime')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_time_course_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWTIME_TIME_COURSE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ .fcs files, .csv file ] ]

    main:
    BIOC_FLOWTIME_TIME_COURSE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWTIME_TIME_COURSE_ANALYSIS.out.tables
    plots    = BIOC_FLOWTIME_TIME_COURSE_ANALYSIS.out.plots
    objects  = BIOC_FLOWTIME_TIME_COURSE_ANALYSIS.out.objects
    versions = BIOC_FLOWTIME_TIME_COURSE_ANALYSIS.out.versions
}
