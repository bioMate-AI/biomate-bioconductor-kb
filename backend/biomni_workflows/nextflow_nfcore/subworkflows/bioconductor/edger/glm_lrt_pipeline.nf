#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edgeR — glm_lrt_pipeline
// Perform differential expression analysis for complex multifactor designs using negative binomial GLMs and likelihood ratio tests.
// Input: y
// Container: quay.io/biocontainers/bioconductor-edger:4.8.2--r45h01b2380_0
// R packages: edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: edgeR
// Visualizations: mean-difference plot
// QC: dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define design matrix
//  * 2. [Core Analysis] Estimate dispersions with design matrix
//  * 3. [Core Analysis] Fit negative binomial GLM
//  * 4. [Core Analysis] Perform likelihood ratio test for specific coefficients or contrasts
//  * 5. [Core Analysis] Extract top tags

nextflow.enable.dsl = 2

process BIOC_EDGER_GLM_LRT_PIPELINE {
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
    .bm_deps <- c("edgeR")
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
        library(edgeR)
        
        # Read user input (DGEList object)
        # The pipeline expects a file named 'y.rds' in the working directory containing the DGEList object.
        if (!file.exists("y.rds")) {
          stop("Input file 'y.rds' not found in the working directory.")
        }
        y <- readRDS("y.rds")
        
        # 1. Define design matrix
        group <- factor(y\$samples\$group)
        design <- model.matrix(~group)
        
        # 2. Estimate dispersions with design matrix
        y <- estimateDisp(y, design)
        
        # 3. Fit negative binomial GLM
        fit <- glmFit(y, design)
        
        # 4. Perform likelihood ratio test for specific coefficients or contrasts
        lrt.2vs1 <- glmLRT(fit, coef=2)
        
        # 5. Extract top tags
        results <- topTags(lrt.2vs1)
        
        # Write named output files for the meaningful results
        # Save the top tags table as CSV
        write.csv(as.data.frame(results), file = "top_tags_lrt_2vs1.csv", row.names = TRUE)
        
        # Save the LRT object, fit object, and updated DGEList object as RDS
        saveRDS(lrt.2vs1, file = "lrt_2vs1.rds")
        saveRDS(fit, file = "glm_fit.rds")
        saveRDS(y, file = "y_estimated_disp.rds")
        
        # Generate and save a Mean-Difference (MD) plot
        pdf("md_plot_lrt_2vs1.pdf")
        plotMD(lrt.2vs1)
        abline(h=c(-1, 1), col="blue")
        dev.off()

    writeLines(c(
        '"BIOC_EDGER_GLM_LRT_PIPELINE":',
        paste0('    edgeR: ', as.character(packageVersion('edgeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glm_lrt_pipeline.csv versions.yml
    """
}

workflow BIOC_EDGER_GLM_LRT_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y ] ]

    main:
    BIOC_EDGER_GLM_LRT_PIPELINE(ch_input)

    emit:
    tables   = BIOC_EDGER_GLM_LRT_PIPELINE.out.tables
    plots    = BIOC_EDGER_GLM_LRT_PIPELINE.out.plots
    objects  = BIOC_EDGER_GLM_LRT_PIPELINE.out.objects
    versions = BIOC_EDGER_GLM_LRT_PIPELINE.out.versions
}
