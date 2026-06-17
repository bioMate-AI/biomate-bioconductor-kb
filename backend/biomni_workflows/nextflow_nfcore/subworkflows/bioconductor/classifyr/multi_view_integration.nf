#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClassifyR — multi_view_integration
// Integrate data from multiple sources/assays into a single classification model using crossValidate.
// Input: measurementsDF, classes
// Container: quay.io/biocontainers/bioconductor-classifyr:3.14.0--r45ha27e39d_0
// R packages: ClassifyR, S4Vectors
// Bioconductor: 3.20 | R: 4.4
// Requires: ClassifyR, S4Vectors
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare multi-view data (either as a DataFrame with assay metadata or as a named list of data.frames)
//  * 2. [Core Analysis] Run cross-validation with multiViewMethod = "merge"
//  * 3. [Visualization & Output] Plot performance grouped by assay

nextflow.enable.dsl = 2

process BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("ClassifyR", "S4Vectors")
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
        
        library(ClassifyR)
        library(S4Vectors)
        
        # Set seed for reproducibility as recommended by ClassifyR documentation
        set.seed(9500)
        
        # Read the required classes input
        if (!file.exists("classes.rds")) {
          stop("Error: 'classes.rds' file not found in the working directory.")
        }
        classes <- readRDS("classes.rds")
        
        # Check for DataFrame input
        if (file.exists("measurementsDF.rds")) {
          measurementsDF <- readRDS("measurementsDF.rds")
          
          # Run cross-validation using the DataFrame multi-view integration workflow
          result_df <- crossValidate(measurementsDF, classes, classifier = "SVM", nFolds = 5,
                                     nRepeats = 3, multiViewMethod = "merge")
          
          # Save the ClassifyResult object
          saveRDS(result_df, "result_df.rds")
          
          # Generate and save the performance plot
          pdf("performance_plot_df.pdf", width = 7, height = 6)
          print(performancePlot(result_df, characteristicsList = list(x = "Assay Name")))
          dev.off()
        }
        
        # Check for List input
        if (file.exists("measurementsList.rds")) {
          measurementsList <- readRDS("measurementsList.rds")
          
          # Run cross-validation using the list of data.frames multi-view integration workflow
          result_list <- crossValidate(measurementsList, classes, classifier = "SVM", nFolds = 5,
                                       nRepeats = 3, multiViewMethod = "merge")
          
          # Save the ClassifyResult object
          saveRDS(result_list, "result_list.rds")
          
          # Generate and save the performance plot
          pdf("performance_plot_list.pdf", width = 7, height = 6)
          print(performancePlot(result_list, characteristicsList = list(x = "Assay Name")))
          dev.off()
        }
        
        if (!file.exists("measurementsDF.rds") && !file.exists("measurementsList.rds")) {
          stop("Error: Neither 'measurementsDF.rds' nor 'measurementsList.rds' was found in the working directory.")
        }

    writeLines(c(
        '"BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION":',
        paste0('    ClassifyR: ', as.character(packageVersion('ClassifyR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_view_integration.csv versions.yml
    """
}

workflow BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ measurementsDF, classes ] ]

    main:
    BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION.out.tables
    plots    = BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION.out.plots
    objects  = BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION.out.objects
    versions = BIOC_CLASSIFYR_MULTI_VIEW_INTEGRATION.out.versions
}
