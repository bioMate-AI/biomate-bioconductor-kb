#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NormalyzerDE — stepwise_processing
// Execute the normalization and differential expression pipelines step-by-step for custom control.
// Input: tiny_data.tsv, tiny_design.tsv
// Container: quay.io/biocontainers/bioconductor-normalyzerde:1.28.0--r45hdfd78af_0
// Requires: NormalyzerDE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Setup raw data object using setupRawDataObject
//  * 2. [Core Analysis] Verify input using getVerifiedNormalyzerObject
//  * 3. [Core Analysis] Perform normalizations using normMethods
//  * 4. [Core Analysis] Analyze normalizations using analyzeNormalizations
//  * 5. [Visualization & Output] Setup job directory using setupJobDir and write matrices using writeNormalizedDatasets
//  * 6. [Visualization & Output] Generate evaluation plots using generatePlots
//  * 7. [Core Analysis] Setup raw contrast object using setupRawContrastObject
//  * 8. [Core Analysis] Initialize statistics object using NormalyzerStatistics
//  * 9. [Core Analysis] Calculate contrasts using calculateContrasts
//  * 10. [Visualization & Output] Generate annotated matrix using generateAnnotatedMatrix and write to file
//  * 11. [Visualization & Output] Generate statistics report using generateStatsReport

nextflow.enable.dsl = 2

process BIOC_NORMALYZERDE_STEPWISE_PROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("NormalyzerDE")
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
    library(NormalyzerDE)
    
    # Define input file paths as specified by user input
    dataFp <- "tiny_data.tsv"
    designFp <- "tiny_design.tsv"
    
    # Verify input files exist
    if (!file.exists(dataFp)) {
      stop("Error: Input file 'tiny_data.tsv' not found in the working directory.")
    }
    if (!file.exists(designFp)) {
      stop("Error: Input file 'tiny_design.tsv' not found in the working directory.")
    }
    
    # Step 1: Setup raw data object
    jobName <- "vignette_run"
    experimentObj <- setupRawDataObject(dataFp, designFp, "default", TRUE, "sample", "group")
    
    # Step 2: Verify input
    normObj <- getVerifiedNormalyzerObject(jobName, experimentObj)
    
    # Step 3: Perform normalizations
    normResults <- normMethods(normObj)
    
    # Step 4: Analyze normalizations
    normResultsWithEval <- analyzeNormalizations(normResults)
    
    # Step 5: Setup job directory and write normalized datasets
    jobDir <- setupJobDir("vignette_run", tempdir())
    writeNormalizedDatasets(normResultsWithEval, jobDir)
    
    # Step 6: Generate evaluation plots
    generatePlots(normResultsWithEval, jobDir)
    
    # Step 7: Setup raw contrast object
    bestNormMatPath <- paste(jobDir, "RT-Loess-normalized.txt", sep="/")
    experimentObj <- setupRawContrastObject(bestNormMatPath, designFp, "sample")
    
    # Step 8: Initialize statistics object
    nst <- NormalyzerStatistics(experimentObj, logTrans=FALSE)
    
    # Step 9: Calculate contrasts
    comparisons <- c("4-5")
    nst <- calculateContrasts(nst, comparisons, condCol="group", leastRepCount=2)
    
    # Step 10: Generate annotated matrix and write to file
    annotDf <- generateAnnotatedMatrix(nst)
    utils::write.table(annotDf, file=paste(jobDir, "stat_table.tsv", sep="/"))
    
    # Step 11: Generate statistics report
    generateStatsReport(nst, "Vignette stats", jobDir)
    
    # Save final outputs to the current working directory for easy access
    write.table(annotDf, file="stat_table_output.tsv", sep="\t", row.names=FALSE, quote=FALSE)
    saveRDS(normResultsWithEval, file="normResultsWithEval.rds")
    saveRDS(nst, file="normalyzer_statistics.rds")
    
    # Copy all generated reports, plots, and matrices to the working directory
    generated_files <- list.files(jobDir, full.names = TRUE, recursive = TRUE)
    for (f in generated_files) {
      if (!dir.exists(f)) {
        file.copy(f, "./", overwrite = TRUE)
      }
    }

    writeLines(c(
        '"BIOC_NORMALYZERDE_STEPWISE_PROCESSING":',
        paste0('    NormalyzerDE: ', as.character(packageVersion('NormalyzerDE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stepwise_processing.csv versions.yml
    """
}

workflow BIOC_NORMALYZERDE_STEPWISE_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tiny_data.tsv, tiny_design.tsv ] ]

    main:
    BIOC_NORMALYZERDE_STEPWISE_PROCESSING(ch_input)

    emit:
    tables   = BIOC_NORMALYZERDE_STEPWISE_PROCESSING.out.tables
    plots    = BIOC_NORMALYZERDE_STEPWISE_PROCESSING.out.plots
    objects  = BIOC_NORMALYZERDE_STEPWISE_PROCESSING.out.objects
    versions = BIOC_NORMALYZERDE_STEPWISE_PROCESSING.out.versions
}
