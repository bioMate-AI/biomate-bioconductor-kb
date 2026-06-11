#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HybridMTest — regression_analysis
// Perform hybrid correlation testing using Pearson and Spearman tests weighted by Shapiro-Wilk normality test EBPs.
// Input: correlation.data
// Container: quay.io/biocontainers/bioconductor-hybridmtest:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, HybridMTest
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and the correlation dataset
//  * 2. [Core Analysis] Extract expression and phenotype data for inspection
//  * 3. [Input & Preparation] Define the test specifications mapping to row-wise test functions
//  * 4. [Input & Preparation] Define the EBP weighting rules using the Shapiro-Wilk EBP
//  * 5. [Core Analysis] Run the hybrid test using hybrid.test and view results

nextflow.enable.dsl = 2

process BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS {
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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # 1. Load the required packages
    library(HybridMTest)
    library(Biobase)
    
    # 2. Read the user input file from the working directory
    if (!file.exists("correlation.data")) {
      stop("Error: Required input file 'correlation.data' not found in the working directory.")
    }
    
    # Robustly load the ExpressionSet object from the file
    correlation.data <- tryCatch({
      readRDS("correlation.data")
    }, error = function(e) {
      # Fallback to loading as RData/saved workspace if RDS read fails
      env <- new.env()
      load("correlation.data", envir = env)
      objs <- ls(env)
      eset_idx <- sapply(objs, function(o) inherits(env[[o]], "ExpressionSet"))
      if (any(eset_idx)) {
        env[[objs[which(eset_idx)[1]]]]
      } else if (length(objs) > 0) {
        env[[objs[1]]]
      } else {
        stop("Error: Failed to extract an ExpressionSet object from 'correlation.data'.")
      }
    })
    
    if (!inherits(correlation.data, "ExpressionSet")) {
      stop("Error: Loaded object is not of class 'ExpressionSet'.")
    }
    
    # Extract expression and phenotype data for inspection
    Y <- exprs(correlation.data)
    x <- pData(correlation.data)
    
    # 3. Define the test specifications mapping to row-wise test functions
    test.specs <- cbind.data.frame(label=c("pearson","spearman","shapiro"),
                                 func.name=c("row.pearson","row.spearman","row.slr.shapiro"),
                                 x=rep("x",3),
                                 opts=rep("",3))
    
    # 4. Define the EBP weighting rules using the Shapiro-Wilk EBP
    ebp.def <- cbind.data.frame(wght=c("shapiro.ebp","(1-shapiro.ebp)"),
                              mthd=c("pearson.ebp","spearman.ebp"))
    
    # 5. Run the hybrid test using hybrid.test and view results
    corr.res <- hybrid.test(correlation.data,test.specs,ebp.def)
    print(head(corr.res))
    
    # 6. Write meaningful output files
    write.csv(corr.res, file = "hybrid_test_results.csv", row.names = TRUE)
    saveRDS(corr.res, file = "hybrid_test_results.rds")
    
    # Generate diagnostic plots of the results
    pdf("hybrid_test_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    if ("best.pval" %in% colnames(corr.res)) {
      hist(corr.res\$best.pval, 
           main = "Distribution of Best P-values", 
           xlab = "P-value", 
           col = "skyblue", 
           breaks = 20)
    }
    
    if ("wgt.mean.ebp" %in% colnames(corr.res)) {
      hist(corr.res\$wgt.mean.ebp, 
           main = "Distribution of Weighted Mean EBPs", 
           xlab = "Empirical Bayes Probability (EBP)", 
           col = "salmon", 
           breaks = 20)
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS":',
        paste0('    HybridMTest: ', as.character(packageVersion('HybridMTest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regression_analysis.csv versions.yml
    """
}

workflow BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ correlation.data ] ]

    main:
    BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS.out.tables
    plots    = BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS.out.plots
    objects  = BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS.out.objects
    versions = BIOC_HYBRIDMTEST_REGRESSION_ANALYSIS.out.versions
}
