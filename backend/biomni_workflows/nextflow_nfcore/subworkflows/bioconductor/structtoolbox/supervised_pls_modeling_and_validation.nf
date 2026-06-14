#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: structToolbox — supervised_pls_modeling_and_validation
// Perform supervised PLS-DA and PLSR modeling on pre-processed metabolomics data, validate model performance using cross-validation and permutation testing, and g
// Input: sacurine
// Container: quay.io/biocontainers/bioconductor-structtoolbox:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cowplot, ggplot2, structToolbox
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert input list to DatasetExperiment
//  * 2. [Core Analysis] Apply autoscale and PLS-DA to classify samples
//  * 3. [Core Analysis] Convert factor to numeric and apply PLSR
//  * 4. [Visualization & Output] Generate PLSR diagnostic plots (Cook's distance, prediction, QQ, and residual histogram)
//  * 5. [Core Analysis] Perform k-fold cross-validation to estimate R2 and Q2
//  * 6. [Core Analysis] Perform permutation testing to assess model significance

nextflow.enable.dsl = 2

process BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("structToolbox", "ggplot2", "cowplot")
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
    library(structToolbox)
    library(ggplot2)
    library(cowplot)
    
    # 1. Read the declared USER INPUT file from the working directory
    # The input 'sacurine' is expected to be a list containing dataMatrix, sampleMetadata, and variableMetadata.
    # We check for common formats (RDS, RData, or a file named 'sacurine' without extension).
    if (file.exists("sacurine.rds")) {
      sacurine <- readRDS("sacurine.rds")
    } else if (file.exists("sacurine.RData")) {
      load("sacurine.RData")
    } else if (file.exists("sacurine")) {
      sacurine <- readRDS("sacurine")
    } else {
      stop("Required input file 'sacurine' (RDS or RData format) not found in the working directory.")
    }
    
    # 2. Convert input list to DatasetExperiment
    sacurine\$variableMetadata\$annotation=rownames(sacurine\$variableMetadata)
    rownames(sacurine\$variableMetadata)=1:nrow(sacurine\$variableMetadata)
    colnames(sacurine\$dataMatrix)=1:ncol(sacurine\$dataMatrix)
    DE = DatasetExperiment(data = data.frame(sacurine\$dataMatrix),
                           sample_meta = sacurine\$sampleMetadata,
                           variable_meta = sacurine\$variableMetadata,
                           name = 'Sacurine data',
                           description = 'See ropls package documentation for details')
    
    # 3. Apply autoscale and PLS-DA to classify samples
    M = autoscale() + PLSDA(factor_name='gender')
    M = model_apply(M,DE)
    C = pls_scores_plot(factor_name = 'gender')
    p_plsda = chart_plot(C,M[2])
    
    # Save PLS-DA scores plot
    ggsave("plsda_scores_plot.pdf", plot = p_plsda, width = 7, height = 6)
    
    # 4. Convert factor to numeric and apply PLSR
    DE\$sample_meta\$gender=as.numeric(DE\$sample_meta\$gender)
    M = autoscale(mode='both') + PLSR(factor_name='gender',number_components=3)
    M = model_apply(M,DE)
    
    # 5. Generate PLSR diagnostic plots (Cook's distance, prediction, QQ, and residual histogram)
    C = plsr_cook_dist()
    g1 = chart_plot(C,M[2])
    C = plsr_prediction_plot()
    g2 = chart_plot(C,M[2])
    C = plsr_qq_plot()
    g3 = chart_plot(C,M[2])
    C = plsr_residual_hist()
    g4 = chart_plot(C,M[2])
    p_diag = plot_grid(plotlist = list(g1,g2,g3,g4), nrow=2,align='vh')
    
    # Save PLSR diagnostic plots
    ggsave("plsr_diagnostic_plots.pdf", plot = p_diag, width = 10, height = 8)
    
    # 6. Perform k-fold cross-validation to estimate R2 and Q2
    M = kfold_xval(folds=7, factor_name='gender') * 
        (autoscale(mode='both') + PLSR(factor_name='gender'))
    M = run(M,DE,r_squared())
    
    # Save cross-validation metrics
    write.csv(M\$metric, "plsr_cv_metrics.csv", row.names = FALSE)
    
    # 7. Perform permutation testing to assess model significance
    DE\$sample_meta\$gender=sacurine\$sampleMetadata\$gender
    M = permutation_test(number_of_permutations = 10, factor_name='gender') *
        kfold_xval(folds=7,factor_name='gender') *
        (autoscale() + PLSDA(factor_name='gender',number_components = 3))
    M = run(M,DE,balanced_accuracy())
    
    # Save permutation test metrics
    write.csv(M\$metric, "plsda_permutation_metrics.csv", row.names = FALSE)
    
    C = permutation_test_plot(style='boxplot')
    p_perm = chart_plot(C,M)+ylab('1 - balanced accuracy')
    
    # Save permutation test plot
    ggsave("plsda_permutation_plot.pdf", plot = p_perm, width = 7, height = 6)

    writeLines(c(
        '"BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION":',
        paste0('    structToolbox: ', as.character(packageVersion('structToolbox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_pls_modeling_and_validation.csv versions.yml
    """
}

workflow BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sacurine ] ]

    main:
    BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION(ch_input)

    emit:
    tables   = BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION.out.tables
    plots    = BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION.out.plots
    objects  = BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION.out.objects
    versions = BIOC_STRUCTTOOLBOX_SUPERVISED_PLS_MODELING_AND_VALIDATION.out.versions
}
