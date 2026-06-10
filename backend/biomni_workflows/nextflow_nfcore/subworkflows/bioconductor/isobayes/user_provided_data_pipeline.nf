#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IsoBayes — user_provided_data_pipeline
// Perform protein isoform inference using custom user-provided peptide abundance data in .tsv, data.frame, or SummarizedExperiment format.
// Input: X, jurkat_isoform_kallisto.tsv
// Container: quay.io/biocontainers/bioconductor-isobayes:1.8.0--r45ha27e39d_0
// Requires: IsoBayes
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate SummarizedExperiment from custom data using generate_SE with input_type = "other"
//  * 2. [Core Analysis] Preprocess data and integrate TPMs using input_data
//  * 3. [Core Analysis] Run Bayesian inference using inference

nextflow.enable.dsl = 2

process BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE {
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
    .bm_deps <- c("IsoBayes")
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
    library(IsoBayes)
    
    # Define input file paths from the working directory
    X_file <- "X.tsv"
    if (!file.exists(X_file)) {
      if (file.exists("X")) {
        X_file <- "X"
      } else {
        stop("Required input file 'X.tsv' or 'X' not found in the working directory.")
      }
    }
    X <- X_file
    
    tpm_path <- "jurkat_isoform_kallisto.tsv"
    if (!file.exists(tpm_path)) {
      stop("Required input file 'jurkat_isoform_kallisto.tsv' not found in the working directory.")
    }
    
    # 1. Generate SummarizedExperiment from custom data
    SE = generate_SE(path_to_peptides_psm = X,
                     abundance_type = "psm",
                     input_type = "other")
    
    # 2. Preprocess data and integrate TPMs
    data_loaded = input_data(SE, path_to_tpm = tpm_path)
    
    # 3. Run Bayesian inference
    set.seed(169612)
    results = inference(data_loaded)
    
    # Save outputs
    saveRDS(results, "isobayes_results.rds")
    
    if (!is.null(results\$isoform_results)) {
      write.csv(results\$isoform_results, "isoform_results.csv", row.names = FALSE)
    }
    
    if (!is.null(results\$normalized_isoform_results)) {
      write.csv(results\$normalized_isoform_results, "normalized_isoform_results.csv", row.names = FALSE)
    }
    
    if (!is.null(results\$gene_abundance)) {
      write.csv(results\$gene_abundance, "gene_abundance.csv", row.names = FALSE)
    }
    
    message("IsoBayes pipeline completed successfully. Outputs saved.")

    writeLines(c(
        '"BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE":',
        paste0('    IsoBayes: ', as.character(packageVersion('IsoBayes')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_user_provided_data_pipeline.csv versions.yml
    """
}

workflow BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ X, jurkat_isoform_kallisto.tsv ] ]

    main:
    BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE.out.tables
    plots    = BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE.out.plots
    objects  = BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE.out.objects
    versions = BIOC_ISOBAYES_USER_PROVIDED_DATA_PIPELINE.out.versions
}
