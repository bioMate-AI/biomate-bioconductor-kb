#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SigCheck — classification_analysis
// Evaluate a gene signature's binary classification performance independently of survival data.
// Input: nki, knownSignatures$cancer$VANTVEER
// Container: quay.io/biocontainers/bioconductor-sigcheck:2.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, MLInterfaces, SigCheck
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the SigCheckObject with scoreMethod="classifier" and without survival data
//  * 2. [Core Analysis] Inspect baseline classification accuracy, mode performance, and the confusion matrix
//  * 3. [Core Analysis] Run checks against random and known signatures
//  * 4. [Visualization & Output] Plot the classification performance distributions

nextflow.enable.dsl = 2

process BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS {
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
    .bm_deps <- c("SigCheck", "Biobase", "MLInterfaces")
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
    library(SigCheck)
    library(Biobase)
    library(MLInterfaces)
    
    # Read user input files from the working directory
    nki <- readRDS("nki.rds")
    knownSignatures <- readRDS("knownSignatures.rds")
    
    # Remove NAs from the binary class metadata (e.dmfs)
    nki <- nki[,!is.na(nki\$e.dmfs)]
    
    # 1. Initialize the SigCheckObject with scoreMethod="classifier" and without survival data
    check <- sigCheck(nki, classes="e.dmfs",
                      signature=knownSignatures\$cancer\$VANTVEER,
                      annotation="HUGO.gene.symbol",
                      validationSamples=which(nki\$series=="NKI2"),
                      scoreMethod="classifier") 
    
    # 2. Inspect baseline classification accuracy, mode performance, and the confusion matrix
    sigPerf <- check@sigPerformance
    modePerf <- check@modePerformance
    confusionMat <- check@confusion
    
    # Write baseline performance metrics to a CSV file
    performance_summary <- data.frame(
      Metric = c("sigPerformance", "modePerformance"),
      Value = c(sigPerf, modePerf)
    )
    write.csv(performance_summary, "baseline_performance.csv", row.names = FALSE)
    
    # Write confusion matrix to a CSV file
    write.csv(as.data.frame(confusionMat), "confusion_matrix.csv")
    
    # 3. Run checks against random and known signatures
    classifyRandom <- sigCheckRandom(check, iterations=1000)
    classifyKnown <- sigCheckKnown(check)
    
    # Save the resulting SigCheck objects as RDS files
    saveRDS(classifyRandom, "classifyRandom.rds")
    saveRDS(classifyKnown, "classifyKnown.rds")
    
    # 4. Plot the classification performance distributions and save to a PDF file
    pdf("classification_performance_plots.pdf", width = 10, height = 5)
    par(mfrow=c(1,2))
    sigCheckPlot(classifyRandom, classifier=TRUE)
    sigCheckPlot(classifyKnown,  classifier=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS":',
        paste0('    SigCheck: ', as.character(packageVersion('SigCheck')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_classification_analysis.csv versions.yml
    """
}

workflow BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nki, knownSignatures$cancer$VANTVEER ] ]

    main:
    BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS.out.tables
    plots    = BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS.out.plots
    objects  = BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS.out.objects
    versions = BIOC_SIGCHECK_CLASSIFICATION_ANALYSIS.out.versions
}
