#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MIRit — unpaired_integration_workflow
// Perform integration analysis for unpaired miRNA and gene expression data using association tests or rotation gene-set tests.
// Input: experiment
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: MIRit
// Bioconductor: 3.20 | R: 4.4
// Requires: MIRit
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform one-sided inverse association analysis using Fisher's exact test with mid-p correction
//  * 2. [Core Analysis] Perform integrative analysis using the rotation gene-set test (fry) method

nextflow.enable.dsl = 2

process BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW {
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
    .bm_deps <- c("MIRit")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(MIRit)
    
    # Read user input
    # The user input is a MirnaExperiment object containing differential expression results and retrieved miRNA targets
    experiment <- readRDS("experiment.rds")
    
    # Stage 1: Perform one-sided inverse association analysis using Fisher's exact test with mid-p correction
    exp.association <- mirnaIntegration(experiment,
                                        test = "association",
                                        associationMethod = "fisher-midp",
                                        pCutoff = 0.2,
                                        pAdjustment = "none")
    
    # Stage 2: Perform integrative analysis using the rotation gene-set test (fry) method
    exp.fry <- mirnaIntegration(experiment,
                                test = "fry",
                                pAdjustment = "none")
    
    # Save results
    # 1. Save RDS objects
    saveRDS(exp.association, "exp_association.rds")
    saveRDS(exp.fry, "exp_fry.rds")
    
    # 2. Extract and save tabular results
    assoc_results <- integration(exp.association)
    write.csv(assoc_results, "association_results.csv", row.names = FALSE)
    
    fry_results <- integration(exp.fry)
    write.csv(fry_results, "fry_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW":',
        paste0('    MIRit: ', as.character(packageVersion('MIRit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unpaired_integration_workflow.csv versions.yml
    """
}

workflow BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experiment ] ]

    main:
    BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW.out.tables
    plots    = BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW.out.plots
    objects  = BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW.out.objects
    versions = BIOC_MIRIT_UNPAIRED_INTEGRATION_WORKFLOW.out.versions
}
