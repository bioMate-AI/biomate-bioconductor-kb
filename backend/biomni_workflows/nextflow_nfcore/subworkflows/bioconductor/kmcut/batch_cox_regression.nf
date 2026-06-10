#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kmcut — batch_cox_regression
// Fit univariate Cox proportional hazard regression models and perform likelihood ratio tests for all features in batch.
// Input: survival_data.txt, example_genes.txt
// Container: quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KMCUT_BATCH_COX_REGRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kmcut:1.4.0--r45hdfd78af_0"

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
    .bm_deps <- c("kmcut")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(kmcut)
    
    # Define input file paths as specified by the user
    fdat <- "example_genes.txt"
    sdat <- "survival_data.txt"
    
    # Check if input files exist before proceeding
    if (!file.exists(fdat)) {
      stop(paste("Required input file missing:", fdat))
    }
    if (!file.exists(sdat)) {
      stop(paste("Required input file missing:", sdat))
    }
    
    # Create a SummarizedExperiment object 'se' from the input files
    se <- create_se_object(efile = fdat, sfile = sdat)
    
    # Perform batch Cox regression
    # This will automatically write "test_ucoxbatch.txt" to the working directory
    ucox_batch(obj = se, bfname = "test")
    
    # Print a message indicating completion and output location
    cat("Batch Cox regression completed successfully.\n")
    cat("Output written to: test_ucoxbatch.txt\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KMCUT_BATCH_COX_REGRESSION":
        kmcut: \$(Rscript -e 'cat(as.character(packageVersion("kmcut")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_cox_regression.csv versions.yml
    """
}

workflow BIOC_KMCUT_BATCH_COX_REGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ survival_data.txt, example_genes.txt ] ]

    main:
    BIOC_KMCUT_BATCH_COX_REGRESSION(ch_input)

    emit:
    tables   = BIOC_KMCUT_BATCH_COX_REGRESSION.out.tables
    plots    = BIOC_KMCUT_BATCH_COX_REGRESSION.out.plots
    objects  = BIOC_KMCUT_BATCH_COX_REGRESSION.out.objects
    versions = BIOC_KMCUT_BATCH_COX_REGRESSION.out.versions
}
