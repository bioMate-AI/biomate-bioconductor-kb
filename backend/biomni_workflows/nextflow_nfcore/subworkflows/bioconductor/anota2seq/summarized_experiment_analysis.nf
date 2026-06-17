#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: anota2seq — summarized_experiment_analysis
// Perform a rapid, one-step translational efficiency analysis starting from a SummarizedExperiment object.
// Input: mySummarizedExperiment
// Container: quay.io/biocontainers/bioconductor-anota2seq:1.32.0--r45hdfd78af_0
// R packages: SummarizedExperiment, anota2seq
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, anota2seq
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Initialize the Anota2seqDataSet from a SummarizedExperiment using anota2seqDataSetFromSE
//  * 2. [Core Analysis] Run the complete analysis pipeline (QC, outlier tests, and APV analysis) using the wrapper function anota2seqRun
//  * 3. [Visualization & Output] Extract output tables using anota2seqGetOutput

nextflow.enable.dsl = 2

process BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS {
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
    .bm_deps <- c("SummarizedExperiment", "anota2seq")
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
    library(anota2seq)
    
    # Read the user input file from the working directory
    # The input is expected to be a serialized SummarizedExperiment object
    input_file <- "mySummarizedExperiment"
    if (!file.exists(input_file) && file.exists("mySummarizedExperiment.rds")) {
      input_file <- "mySummarizedExperiment.rds"
    }
    
    if (!file.exists(input_file)) {
      stop("Error: Input file 'mySummarizedExperiment' or 'mySummarizedExperiment.rds' not found in the working directory.")
    }
    
    mySummarizedExperiment <- readRDS(input_file)
    
    # 1. Initialize the Anota2seqDataSet from the SummarizedExperiment object
    adsFromSE <- anota2seqDataSetFromSE(
        se = mySummarizedExperiment,
        assayNum = 1,
        dataType = "RNAseq",
        normalize = TRUE,
        transformation = "TMM-log2")
    
    # 2. Run the complete analysis pipeline (QC, outlier tests, and APV analysis)
    adsFromSE <- anota2seqRun(
        Anota2seqDataSet = adsFromSE,
        thresholds = list(
            maxPAdj = 0.05,
            minEff = 1.5),
        performQC = TRUE,
        performROT = TRUE,
        useRVM = TRUE)
    
    # 3. Extract and display the selected output table for translation analysis
    translation_selected <- anota2seqGetOutput(
        adsFromSE, 
        analysis = "translation", 
        output = "selected", 
        getRVM = TRUE, 
        selContrast = 1)
    
    print(head(translation_selected))
    
    # Write meaningful results to output files
    write.csv(translation_selected, file = "translation_selected_output.csv", row.names = TRUE)
    
    # Extract and save the full output table for completeness
    translation_full <- anota2seqGetOutput(
        adsFromSE, 
        analysis = "translation", 
        output = "full", 
        getRVM = TRUE, 
        selContrast = 1)
    write.csv(translation_full, file = "translation_full_output.csv", row.names = TRUE)
    
    # Save the final Anota2seqDataSet object
    saveRDS(adsFromSE, file = "anota2seq_output_dataset.rds")

    writeLines(c(
        '"BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS":',
        paste0('    anota2seq: ', as.character(packageVersion('anota2seq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarized_experiment_analysis.csv versions.yml
    """
}

workflow BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mySummarizedExperiment ] ]

    main:
    BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS.out.tables
    plots    = BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS.out.plots
    objects  = BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS.out.objects
    versions = BIOC_ANOTA2SEQ_SUMMARIZED_EXPERIMENT_ANALYSIS.out.versions
}
