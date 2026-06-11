#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: covRNA — covrna_analysis_workflow
// Perform fourthcorner statistical testing and RLQ ordination to analyze and visualize associations between sample and gene covariates mediated by gene expression
// Input: expression_set.RData, L_matrix.csv, R_df.csv, Q_df.csv
// Container: quay.io/biocontainers/bioconductor-covrna:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, covRNA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and dataset
//  * 2. [Core Analysis] Run fourthcorner analysis using stat to calculate statistical associations
//  * 3. [Visualization & Output] Plot the statistical results using plot
//  * 4. [Core Analysis] Run RLQ ordination using ord
//  * 5. [Visualization & Output] Plot the ordination variance using plot
//  * 6. [Visualization & Output] Combine and visualize both statistical and ordination results using vis

nextflow.enable.dsl = 2

process BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW {
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
    .bm_deps <- c("covRNA", "Biobase")
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
    library(covRNA)
    library(Biobase)
    
    # 1. Read the declared USER INPUT files from the working directory
    L_matrix <- read.csv("L_matrix.csv", row.names = 1, check.names = FALSE)
    R_df <- read.csv("R_df.csv", row.names = 1, check.names = FALSE)
    Q_df <- read.csv("Q_df.csv", row.names = 1, check.names = FALSE)
    
    # Load the ExpressionSet from expression_set.RData
    env <- new.env()
    load("expression_set.RData", envir = env)
    eset_objs <- ls(env)[sapply(ls(env), function(x) is(env[[x]], "ExpressionSet"))]
    
    if (length(eset_objs) > 0) {
      Baca <- env[[eset_objs[1]]]
    } else {
      # Fallback: construct ExpressionSet from the CSV files if not found in RData
      L_mat <- as.matrix(L_matrix)
      Baca <- ExpressionSet(
        assayData = L_mat,
        phenoData = AnnotatedDataFrame(Q_df),
        featureData = AnnotatedDataFrame(R_df)
      )
    }
    
    # 2. Run fourthcorner analysis using stat to calculate statistical associations
    statBaca <- stat(ExprSet = Baca, npermut = 999, padjust = "BH", nrcor = 2, exprvar = 1)
    
    # Save statistical results
    saveRDS(statBaca, "statBaca.rds")
    if (!is.null(statBaca\$adj.pvalue)) {
      write.csv(statBaca\$adj.pvalue, "adjusted_pvalues.csv", row.names = TRUE)
    }
    
    # 3. Plot the statistical results using plot
    # Determine xnames dynamically to prevent crash if user data has different categories,
    # but default to the documented ones if they match.
    actual_categories <- unique(as.character(pData(Baca)[, 1]))
    if (all(c('cold', 'ctrl', 'etoh', 'salt') %in% actual_categories)) {
      xnames_val <- c('cold', 'ctrl', 'etoh', 'salt')
    } else {
      xnames_val <- actual_categories
    }
    
    pdf("stat_plot.pdf")
    plot(statBaca, xnames = xnames_val, shiftx = -0.1)
    dev.off()
    
    # 4. Run RLQ ordination using ord
    ordBaca <- ord(Baca)
    
    # Save ordination results
    saveRDS(ordBaca, "ordBaca.rds")
    
    # 5. Plot the ordination variance using plot
    pdf("ord_variance_plot.pdf")
    plot(ordBaca, feature = "variance")
    dev.off()
    
    # 6. Combine and visualize both statistical and ordination results using vis
    pdf("vis_plot.pdf")
    vis(Stat = statBaca, Ord = ordBaca, rangex = 1.5, rangey = 1.5)
    dev.off()

    writeLines(c(
        '"BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW":',
        paste0('    covRNA: ', as.character(packageVersion('covRNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_covrna_analysis_workflow.csv versions.yml
    """
}

workflow BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData, L_matrix.csv, R_df.csv, Q_df.csv ] ]

    main:
    BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW.out.tables
    plots    = BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW.out.plots
    objects  = BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW.out.objects
    versions = BIOC_COVRNA_COVRNA_ANALYSIS_WORKFLOW.out.versions
}
