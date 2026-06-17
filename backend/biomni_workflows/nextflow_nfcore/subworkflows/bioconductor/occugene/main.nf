#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: occugene — essential_gene_and_knockout_estimation
// Estimate the number of essential genes and predict the number of new gene knockouts in future clones using experimental transposon insertion data and genome ann
// Input: annotation.csv, insertions.csv
// Container: quay.io/biocontainers/bioconductor-occugene:1.70.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: occugene
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load genome annotation and insertion data
//  * 2. [Core Analysis] Format ORF coordinates and clone insertion positions
//  * 3. [Core Analysis] Estimate future knockouts using the Efron and Thisted estimator
//  * 4. [Core Analysis] Fit a nonlinear regression model to cumulative knockouts
//  * 5. [Core Analysis] Estimate future knockouts using the Will and Jacobs' bootstrap
//  * 6. [Core Analysis] Estimate the number of essential genes using the Will and Jacobs' bootstrap
//  * 7. [Core Analysis] Convert data to negenes format if compatibility is needed

nextflow.enable.dsl = 2

process BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("occugene")
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
    library(occugene)
    
    # 1. Load genome annotation and insertion data from user-provided CSV files
    if (!file.exists("annotation.csv") || !file.exists("insertions.csv")) {
      stop("Error: Required input files 'annotation.csv' and/or 'insertions.csv' not found in the working directory.")
    }
    
    a.data <- read.csv("annotation.csv")
    experiment <- read.csv("insertions.csv")
    
    # 2. Format ORF coordinates and clone insertion positions
    orf <- cbind(a.data\$first, a.data\$last)
    clone <- experiment\$position
    
    # 3. Estimate future knockouts using the Efron and Thisted estimator
    et_res <- etDelta(10, orf, clone)
    
    # 4. Fit a nonlinear regression model to cumulative knockouts
    fit_res <- fFit(orf, clone, FALSE)
    
    # 5. Estimate future knockouts using the Will and Jacobs' bootstrap
    unbias_delta_res <- unbiasDelta0(10, orf, clone, iter=10, seed=4, alpha=0.05, TR=F)
    
    # 6. Estimate the number of essential genes using the Will and Jacobs' bootstrap
    unbias_b0_res <- unbiasB0(orf, clone, iter=10, seed=4, alpha=0.05, TR=F)
    
    # 7. Convert data to negenes format if compatibility is needed
    newOrf <- occup2Negenes(orf, clone)
    
    # --- Save Outputs ---
    
    # Save Efron & Thisted results
    et_df <- data.frame(
      expected = et_res\$expected, 
      variance = et_res\$variance
    )
    write.csv(et_df, "et_estimator_results.csv", row.names = FALSE)
    
    # Save nonlinear fit coefficients
    fit_coefs <- coef(fit_res)
    write.csv(as.data.frame(t(fit_coefs)), "nonlinear_fit_coefficients.csv", row.names = FALSE)
    
    # Save unbiasDelta0 results
    delta0_df <- data.frame(
      delta0 = unbias_delta_res\$delta0,
      CI_lower = unbias_delta_res\$CI[1],
      CI_upper = unbias_delta_res\$CI[2]
    )
    write.csv(delta0_df, "bootstrap_delta0_results.csv", row.names = FALSE)
    
    # Save unbiasB0 results
    b0_df <- data.frame(
      b0 = unbias_b0_res\$b0,
      CI_lower = unbias_b0_res\$CI[1],
      CI_upper = unbias_b0_res\$CI[2]
    )
    write.csv(b0_df, "bootstrap_b0_results.csv", row.names = FALSE)
    
    # Save converted negenes format
    write.csv(newOrf, "negenes_format.csv", row.names = FALSE)
    
    # Save all results in a single RDS object for downstream analysis
    saveRDS(list(
      et_results = et_res,
      fit_model = fit_res,
      bootstrap_delta0 = unbias_delta_res,
      bootstrap_b0 = unbias_b0_res,
      negenes_data = newOrf
    ), "occugene_output.rds")
    
    cat("Pipeline completed successfully. Outputs written to the working directory.\n")

    writeLines(c(
        '"BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION":',
        paste0('    occugene: ', as.character(packageVersion('occugene')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_essential_gene_and_knockout_estimation.csv versions.yml
    """
}

workflow BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ annotation.csv, insertions.csv ] ]

    main:
    BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION.out.tables
    plots    = BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION.out.plots
    objects  = BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION.out.objects
    versions = BIOC_OCCUGENE_ESSENTIAL_GENE_AND_KNOCKOUT_ESTIMATION.out.versions
}
