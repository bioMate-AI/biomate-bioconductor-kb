#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RBM — two_group_comparison
// Identify differentially expressed or methylated features between two groups using resampling-based moderated t-statistics.
// Input: ovarian_cancer_methylation.csv, label.csv
// Container: quay.io/biocontainers/bioconductor-rbm:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RBM
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the RBM package and the input dataset
//  * 2. [Input & Preparation] Extract the data matrix and define the group label vector
//  * 3. [Core Analysis] Run RBM_T to compute moderated t-statistics, permutation p-values, and bootstrap p-values
//  * 4. [Core Analysis] Adjust the resulting p-values using the Benjamini-Hochberg method
//  * 5. [Core Analysis] Identify and print significant features based on adjusted p-values

nextflow.enable.dsl = 2

process BIOC_RBM_TWO_GROUP_COMPARISON {
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
    .bm_deps <- c("RBM")
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
        
    # Load required library
    library(RBM)
    
    # 1. Load the input datasets from the working directory
    ovarian_cancer_methylation <- read.csv("ovarian_cancer_methylation.csv", header = TRUE, check.names = FALSE)
    
    # Read label vector
    label_data <- read.csv("label.csv", header = FALSE)
    label <- as.numeric(as.vector(t(label_data)))
    
    # 2. Extract the data matrix and define the group label vector
    ovarian_cancer_data <- as.matrix(ovarian_cancer_methylation[, -1])
    
    # Print summaries to console as in the vignette
    summary(ovarian_cancer_methylation)
    
    # 3. Run RBM_T to compute moderated t-statistics, permutation p-values, and bootstrap p-values
    diff_results <- RBM_T(aData=ovarian_cancer_data, vec_trt=label, repetition=100, alpha=0.05)
    summary(diff_results)
    
    cat("Number of ordinary fit p-values <= 0.05:", sum(diff_results\$ordfit_pvalue<=0.05), "\n")
    cat("Number of permutation p-values <= 0.05:", sum(diff_results\$permutation_p<=0.05), "\n")
    cat("Number of bootstrap p-values <= 0.05:", sum(diff_results\$bootstrap_p<=0.05), "\n")
    
    # 4. Adjust the resulting p-values using the Benjamini-Hochberg method
    ordfit_adjp <- p.adjust(diff_results\$ordfit_pvalue, "BH")
    cat("Number of adjusted ordinary fit p-values <= 0.05:", sum(ordfit_adjp<=0.05), "\n")
    
    perm_adjp <- p.adjust(diff_results\$permutation_p, "BH")
    cat("Number of adjusted permutation p-values <= 0.05:", sum(perm_adjp<=0.05), "\n")
    
    boot_adjp <- p.adjust(diff_results\$bootstrap_p, "BH")
    cat("Number of adjusted bootstrap p-values <= 0.05:", sum(boot_adjp<=0.05), "\n")
    
    # 5. Identify and print significant features based on adjusted p-values
    diff_list_perm <- which(perm_adjp<=0.05)
    diff_list_boot <- which(boot_adjp<=0.05)
    
    sig_results_perm <- cbind(ovarian_cancer_methylation[diff_list_perm, ], diff_results\$ordfit_t[diff_list_perm], diff_results\$permutation_p[diff_list_perm])
    print(sig_results_perm)
    
    sig_results_boot <- cbind(ovarian_cancer_methylation[diff_list_boot, ], diff_results\$ordfit_t[diff_list_boot], diff_results\$bootstrap_p[diff_list_boot])
    print(sig_results_boot)
    
    # Write outputs
    write.csv(sig_results_perm, "sig_results_permutation.csv", row.names = FALSE)
    write.csv(sig_results_boot, "sig_results_bootstrap.csv", row.names = FALSE)
    saveRDS(diff_results, "rbm_t_results.rds")
    
    # Generate PDF plot of p-value distributions
    pdf("pvalue_distributions.pdf", width = 10, height = 4)
    par(mfrow = c(1, 3))
    hist(diff_results\$ordfit_pvalue, main = "Ordinary Fit P-values", xlab = "P-value", col = "lightblue", breaks = 20)
    hist(diff_results\$permutation_p, main = "Permutation P-values", xlab = "P-value", col = "lightgreen", breaks = 20)
    hist(diff_results\$bootstrap_p, main = "Bootstrap P-values", xlab = "P-value", col = "lightpink", breaks = 20)
    dev.off()

    writeLines(c(
        '"BIOC_RBM_TWO_GROUP_COMPARISON":',
        paste0('    RBM: ', as.character(packageVersion('RBM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_group_comparison.csv versions.yml
    """
}

workflow BIOC_RBM_TWO_GROUP_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ovarian_cancer_methylation.csv, label.csv ] ]

    main:
    BIOC_RBM_TWO_GROUP_COMPARISON(ch_input)

    emit:
    tables   = BIOC_RBM_TWO_GROUP_COMPARISON.out.tables
    plots    = BIOC_RBM_TWO_GROUP_COMPARISON.out.plots
    objects  = BIOC_RBM_TWO_GROUP_COMPARISON.out.objects
    versions = BIOC_RBM_TWO_GROUP_COMPARISON.out.versions
}
