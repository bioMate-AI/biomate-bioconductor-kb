#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bacon — adjustment_with_95_ci
// Calculate average inflation- and bias-adjusted statistics with a 95% confidence interval using replicated z-scores.
// Input: zs
// Container: quay.io/biocontainers/bioconductor-bacon:1.38.0--r45h01b2380_0
// Requires: BiocParallel, bacon
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Replicate z-scores into a matrix
//  * 2. [Core Analysis] Run bacon with parallel RNG enabled by setting globalSeed to NULL
//  * 3. [Core Analysis] Calculate mean bias and inflation
//  * 4. [Core Analysis] Calculate 95% confidence intervals using quantile
//  * 5. [Core Analysis] Extract average corrected z-scores and p-values using rowMeans

nextflow.enable.dsl = 2

process BIOC_BACON_ADJUSTMENT_WITH_95_CI {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(bacon)
    library(BiocParallel)
    
    # 1. Read the user input file 'zs' from the working directory
    if (file.exists("zs")) {
      zs_data <- tryCatch({
        read.csv("zs", header = TRUE, row.names = 1)
      }, error = function(e) {
        read.table("zs", header = TRUE, row.names = 1)
      })
    } else if (file.exists("zs.csv")) {
      zs_data <- read.csv("zs.csv", header = TRUE, row.names = 1)
    } else if (file.exists("zs.tsv")) {
      zs_data <- read.delim("zs.tsv", header = TRUE, row.names = 1)
    } else {
      stop("Required input file 'zs' (matrix of replicated z-scores) not found in the working directory.")
    }
    
    # Convert to matrix as required by bacon
    zs <- as.matrix(zs_data)
    
    # Print dimensions and preview of the input matrix
    print("Dimensions of input z-score matrix:")
    print(dim(zs))
    print("First few rows and columns:")
    print(head(zs[, 1:min(5, ncol(zs))]))
    
    # 2. Run bacon with parallel RNG enabled by setting globalSeed to NULL
    register(MulticoreParam(1, log=TRUE))
    bc <- bacon(teststatistics = zs, 
                globalSeed = NULL,
                parallelSeed = 42)
    
    # Print the bacon object summary
    print(bc)
    
    # Display head of inflation and bias
    print("Head of inflation:")
    print(head(inflation(bc)))
    print("Head of bias:")
    print(head(bias(bc)))
    
    # 3. Calculate mean bias and inflation
    mean_bias <- mean(bias(bc))
    print(paste("Mean Bias:", mean_bias))
    
    mean_inflation <- mean(inflation(bc))
    print(paste("Mean Inflation:", mean_inflation))
    
    # 4. Calculate 95% confidence intervals using quantile
    CI_bias <- quantile(bias(bc), c(0.025, 0.975))
    print("95% CI for Bias:")
    print(CI_bias)
    
    CI_inflation <- quantile(inflation(bc), c(0.025, 0.975))
    print("95% CI for Inflation:")
    print(CI_inflation)
    
    # 5. Extract average corrected z-scores and p-values using rowMeans
    avg_corrected_zs <- rowMeans(tstat(bc))
    print("First few average corrected z-scores:")
    print(avg_corrected_zs[1:5])
    
    avg_corrected_pvals <- rowMeans(bacon::pval(bc))
    print("First few average corrected p-values:")
    print(avg_corrected_pvals[1:5])
    
    # 6. Write named output files for the results
    # Save the full Bacon object
    saveRDS(bc, "bacon_object.rds")
    
    # Save the summary metrics (mean and 95% CI)
    summary_metrics <- data.frame(
      Metric = c("mean_bias", "mean_inflation", "CI_bias_0.025", "CI_bias_0.975", "CI_inflation_0.025", "CI_inflation_0.975"),
      Value = c(mean_bias, mean_inflation, CI_bias[1], CI_bias[2], CI_inflation[1], CI_inflation[2])
    )
    write.csv(summary_metrics, "bias_inflation_summary.csv", row.names = FALSE)
    
    # Save the corrected statistics for each feature
    corrected_stats <- data.frame(
      feature_id = rownames(zs),
      avg_corrected_z = avg_corrected_zs,
      avg_corrected_pval = avg_corrected_pvals
    )
    write.csv(corrected_stats, "corrected_statistics.csv", row.names = FALSE)
    
    print("Pipeline completed successfully. Outputs written to 'bacon_object.rds', 'bias_inflation_summary.csv', and 'corrected_statistics.csv'.")

    writeLines(c(
        '"BIOC_BACON_ADJUSTMENT_WITH_95_CI":',
        paste0('    bacon: ', as.character(packageVersion('bacon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adjustment_with_95_ci.csv versions.yml
    """
}

workflow BIOC_BACON_ADJUSTMENT_WITH_95_CI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zs ] ]

    main:
    BIOC_BACON_ADJUSTMENT_WITH_95_CI(ch_input)

    emit:
    tables   = BIOC_BACON_ADJUSTMENT_WITH_95_CI.out.tables
    plots    = BIOC_BACON_ADJUSTMENT_WITH_95_CI.out.plots
    objects  = BIOC_BACON_ADJUSTMENT_WITH_95_CI.out.objects
    versions = BIOC_BACON_ADJUSTMENT_WITH_95_CI.out.versions
}
