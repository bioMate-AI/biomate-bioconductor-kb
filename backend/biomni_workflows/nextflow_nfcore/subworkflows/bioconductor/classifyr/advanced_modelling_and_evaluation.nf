#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClassifyR — advanced_modelling_and_evaluation
// Perform fine-grained cross-validation using runTests with custom parameters, calculate performance metrics, and generate diagnostic plots.
// Input: measurements, classes
// Container: quay.io/biocontainers/bioconductor-classifyr:3.14.0--r45ha27e39d_0
// R packages: ClassifyR
// Bioconductor: 3.20 | R: 4.4
// Requires: ClassifyR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define cross-validation parameters using CrossValParams
//  * 2. [Core Analysis] Run default differential means (DM) model using runTests
//  * 3. [Visualization & Output] Plot top selected features using plotFeatureClasses
//  * 4. [Core Analysis] Calculate performance metrics using calcCVperformance
//  * 5. [Input & Preparation] Define and run a custom differential distribution (DD) model using ModellingParams
//  * 6. [Core Analysis] Compare models using samplesMetricMap, performancePlot, rankingPlot, and ROCplot

nextflow.enable.dsl = 2

process BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION {
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
    .bm_deps <- c("ClassifyR")
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
    library(ClassifyR)
    library(grid)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    if (file.exists("measurements.rds")) {
      measurements <- readRDS("measurements.rds")
    } else if (file.exists("measurements.csv")) {
      measurements <- read.csv("measurements.csv", row.names = 1, check.names = FALSE)
    } else {
      stop("Error: measurements file (measurements.rds or measurements.csv) not found in the working directory.")
    }
    
    if (file.exists("classes.rds")) {
      classes <- readRDS("classes.rds")
    } else if (file.exists("classes.csv")) {
      classes_df <- read.csv("classes.csv", header = TRUE)
      classes <- classes_df[[1]]
    } else {
      stop("Error: classes file (classes.rds or classes.csv) not found in the working directory.")
    }
    
    # Ensure classes is a factor
    if (!is.factor(classes)) {
      classes <- as.factor(classes)
    }
    
    # ==========================================
    # 2. Execute Documented Workflow
    # ==========================================
    
    # Define cross-validation parameters
    crossValParams <- CrossValParams(permutations = 5)
    
    # Run default differential means (DM) model
    DMresults <- runTests(measurements, classes, crossValParams, verbose = 1)
    
    # Plot top selected features
    selectionPercentages <- distribution(DMresults, plot = FALSE)
    write.csv(as.data.frame(selectionPercentages), "selection_percentages.csv", row.names = TRUE)
    
    sortedPercentages <- head(selectionPercentages[order(selectionPercentages, decreasing = TRUE)])
    write.csv(as.data.frame(sortedPercentages), "sorted_percentages.csv", row.names = TRUE)
    
    mostChosen <- sortedPercentages[1]
    bestGenePlot <- plotFeatureClasses(measurements, classes, names(mostChosen), dotBinWidth = 0.1,
                                       xAxisLabel = "Normalised Expression")
    
    # Save the best gene plot
    pdf("best_gene_plot.pdf")
    grid.draw(bestGenePlot[[1]])
    dev.off()
    
    # Calculate performance metrics
    DMresults <- calcCVperformance(DMresults)
    saveRDS(DMresults, "DMresults.rds")
    
    dm_perf <- performance(DMresults)
    saveRDS(dm_perf, "DM_performance.rds")
    
    # Define and run custom differential distribution (DD) model
    modellingParamsDD <- ModellingParams(selectParams = SelectParams("KL"),
                                         trainParams = TrainParams("naiveBayes"),
                                         predictParams = NULL)
    DDresults <- runTests(measurements, classes, crossValParams, modellingParamsDD, verbose = 1)
    saveRDS(DDresults, "DDresults.rds")
    
    # Compare models
    resultsList <- list(Abundance = DMresults, Distribution = DDresults)
    
    # Generate diagnostic plots
    pdf("samples_metric_map.pdf")
    tryCatch({
      smm <- samplesMetricMap(resultsList, showXtickLabels = FALSE)
      grid.draw(smm)
    }, error = function(e) {
      warning("Could not generate samples metric map: ", e\$message)
    })
    dev.off()
    
    pdf("performance_plot.pdf")
    tryCatch({
      print(performancePlot(resultsList))
    }, error = function(e) {
      warning("Could not generate performance plot: ", e\$message)
    })
    dev.off()
    
    pdf("ranking_plot.pdf")
    tryCatch({
      print(rankingPlot(DDresults, topRanked = 1:100, xLabelPositions = c(1, seq(10, 100, 10))))
    }, error = function(e) {
      warning("Could not generate ranking plot: ", e\$message)
    })
    dev.off()
    
    pdf("roc_plot.pdf")
    tryCatch({
      print(ROCplot(resultsList, fontSizes = c(24, 12, 12, 12, 12)))
    }, error = function(e) {
      warning("Could not generate ROC plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION":',
        paste0('    ClassifyR: ', as.character(packageVersion('ClassifyR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_advanced_modelling_and_evaluation.csv versions.yml
    """
}

workflow BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ measurements, classes ] ]

    main:
    BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION(ch_input)

    emit:
    tables   = BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION.out.tables
    plots    = BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION.out.plots
    objects  = BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION.out.objects
    versions = BIOC_CLASSIFYR_ADVANCED_MODELLING_AND_EVALUATION.out.versions
}
