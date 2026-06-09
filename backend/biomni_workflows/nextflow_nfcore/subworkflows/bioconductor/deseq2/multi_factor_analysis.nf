#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DESeq2 — multi_factor_analysis
// Perform differential expression analysis controlling for additional batch or technical covariates.
// Input: dds
// Container: quay.io/biocontainers/bioconductor-deseq2:1.50.2--r45ha27e39d_0
// Requires: DESeq2
// Visualizations: MA plot
// QC: diagnostic MA/PCA QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Update design formula to include covariates
//  * 2. [Core Analysis] Run DESeq() pipeline
//  * 3. [Core Analysis] Extract results for the primary condition
//  * 4. [Core Analysis] Extract results for the covariate using contrasts

nextflow.enable.dsl = 2

process BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
    # Load required libraries
    library(DESeq2)
    
    # Locate and read the user input file
    input_file <- "dds"
    if (!file.exists(input_file) && file.exists("dds.rds")) {
      input_file <- "dds.rds"
    }
    
    if (!file.exists(input_file)) {
      stop("Error: Input file 'dds' or 'dds.rds' not found in the working directory.")
    }
    
    # Load the DESeqDataSet object
    ddsMF <- readRDS(input_file)
    
    # 1. Extract design variables from the existing design formula
    design_vars <- all.vars(design(ddsMF))
    if (length(design_vars) < 2) {
      stop("Error: The design formula must contain at least two variables for multi-factor analysis.")
    }
    covariate <- design_vars[length(design_vars) - 1]
    primary_condition <- design_vars[length(design_vars)]
    
    # 2. Run DESeq() pipeline
    ddsMF <- DESeq(ddsMF)
    
    # 3. Extract results for the primary condition
    resMF <- results(ddsMF)
    
    # 4. Extract results for the covariate using contrasts
    covariate_levels <- levels(as.factor(colData(ddsMF)[[covariate]]))
    resMFType <- results(ddsMF,
                         contrast=c(covariate, covariate_levels[2], covariate_levels[1]))
    
    # Write meaningful output files
    # Save results tables as CSV
    write.csv(as.data.frame(resMF), file = paste0("results_multi_factor_", primary_condition, ".csv"), row.names = TRUE)
    write.csv(as.data.frame(resMFType), file = paste0("results_multi_factor_", covariate, ".csv"), row.names = TRUE)
    
    # Save the updated DESeqDataSet object
    saveRDS(ddsMF, file = "ddsMF_analyzed.rds")
    
    # Generate diagnostic MA-plots
    pdf("multi_factor_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    plotMA(resMF, main = "MA-plot: Primary Condition")
    plotMA(resMFType, main = paste0("MA-plot: Covariate (", covariate, ")"))
    dev.off()

    writeLines(c(
        '"BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS":',
        paste0('    DESeq2: ', as.character(packageVersion('DESeq2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_factor_analysis.csv versions.yml
    """
}

workflow BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds ] ]

    main:
    BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.tables
    plots    = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.plots
    objects  = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.objects
    versions = BIOC_DESEQ2_MULTI_FACTOR_ANALYSIS.out.versions
}
