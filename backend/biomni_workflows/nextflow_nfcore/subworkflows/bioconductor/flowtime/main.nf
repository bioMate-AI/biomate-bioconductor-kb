#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowTime — steady_state_analysis
// Analyze single time-point flow cytometry data by annotating, gating, and compiling individual events.
// Input: .fcs files, .csv file
// Container: quay.io/biocontainers/bioconductor-flowtime:1.34.0--r45hdfd78af_0
// R packages: biocmanager, dplyr, flowClust, flowCore, flowStats, flowTime, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowTime, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import FCS files using read.flowSet
//  * 2. [Input & Preparation] Load metadata annotation using read.csv
//  * 3. [Core Analysis] Annotate the flowSet using annotateFlowSet
//  * 4. [Input & Preparation] Load default gates using loadGates
//  * 5. [Core Analysis] Gate and compile events using steadyState
//  * 6. [Visualization & Output] Plot the compiled events using ggplot

nextflow.enable.dsl = 2

process BIOC_FLOWTIME_STEADY_STATE_ANALYSIS {
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
    .bm_deps <- c("biocmanager", "dplyr", "flowClust", "flowCore", "flowStats", "flowTime", "ggplot2")
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
    library(flowCore)
    library(flowTime)
    library(ggplot2)
    
    # 1. Import FCS files from the working directory
    fcs_files <- list.files(pattern = "\\\\.fcs\$", ignore.case = TRUE)
    if (length(fcs_files) == 0) {
      stop("Error: No .fcs files found in the working directory.")
    }
    
    dat <- read.flowSet(path = ".", pattern = "\\\\.fcs\$", alter.names = TRUE)
    
    # 2. Load metadata annotation using read.csv
    csv_files <- list.files(pattern = "\\\\.csv\$", ignore.case = TRUE)
    if (length(csv_files) == 0) {
      stop("Error: No .csv annotation file found in the working directory.")
    }
    annotation <- read.csv(csv_files[1])
    
    # Find the column in annotation that matches the sample names
    merge_col <- names(annotation)[sapply(annotation, function(x) all(sampleNames(dat) %in% x))][1]
    if (is.na(merge_col)) {
      stop("Error: No column in the annotation file matches the FCS file names.")
    }
    
    # 3. Annotate the flowSet using annotateFlowSet
    adat <- annotateFlowSet(yourFlowSet = dat, annotation_df = annotation, mergeBy = merge_col)
    
    # 4. Load default gates using loadGates
    loadGates()
    
    # 5. Gate and compile events using steadyState
    dat.SS <- steadyState(flowset = adat, ploidy = "diploid", only = "singlets")
    
    # 6. Plot the compiled events using ggplot
    # Dynamically select columns for plotting to avoid hardcoding
    meta_cols <- setdiff(colnames(annotation), merge_col)
    x_col <- if (length(meta_cols) > 0) meta_cols[1] else merge_col
    y_col <- colnames(dat)[1]
    
    p <- ggplot(dat.SS, aes(x = as.factor(.data[[x_col]]), y = .data[[y_col]])) +
      geom_boxplot(outlier.shape = NA) +
      theme_classic(base_family = "Arial", base_size = 16) +
      xlab(x_col) +
      ylab(y_col) +
      theme(legend.position = "none")
    
    # Save meaningful results to files
    write.csv(dat.SS, "steady_state_events.csv", row.names = FALSE)
    ggsave("steady_state_plot.pdf", plot = p, width = 8, height = 6)
    saveRDS(adat, "annotated_flowset.rds")

    writeLines(c(
        '"BIOC_FLOWTIME_STEADY_STATE_ANALYSIS":',
        paste0('    flowTime: ', as.character(packageVersion('flowTime')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_steady_state_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWTIME_STEADY_STATE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ .fcs files, .csv file ] ]

    main:
    BIOC_FLOWTIME_STEADY_STATE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWTIME_STEADY_STATE_ANALYSIS.out.tables
    plots    = BIOC_FLOWTIME_STEADY_STATE_ANALYSIS.out.plots
    objects  = BIOC_FLOWTIME_STEADY_STATE_ANALYSIS.out.objects
    versions = BIOC_FLOWTIME_STEADY_STATE_ANALYSIS.out.versions
}
