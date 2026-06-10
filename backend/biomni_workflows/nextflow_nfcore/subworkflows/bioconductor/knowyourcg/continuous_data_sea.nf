#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowYourCG — continuous_data_sea
// Perform Set Enrichment Analysis (SEA) when either the query or the database is continuous.
// Input: named numeric vector
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// Requires: knowYourCG, sesame
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load continuous query
//  * 2. [Core Analysis] Run set enrichment analysis

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("knowYourCG", "sesame")
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
        
    # Load required libraries
    library(knowYourCG)
    library(sesame)
    
    # 1. Load continuous query from user input
    input_file <- "continuous_query.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: User input file", input_file, "not found in the working directory."))
    }
    
    query <- readRDS(input_file)
    beta_values <- query
    
    # 2. Run set enrichment analysis (SEA)
    # First analysis: query vs seqContextN
    res <- testEnrichmentSEA(query, "seqContextN")
    
    # Save first results
    write.csv(res, "enrichment_results_seqContextN.csv", row.names = FALSE)
    saveRDS(res, "enrichment_results_seqContextN.rds")
    
    # Second analysis: beta_values vs chromHMM
    res <- testEnrichmentSEA(beta_values, "chromHMM")
    
    # Save second results
    write.csv(res, "enrichment_results_chromHMM.csv", row.names = FALSE)
    saveRDS(res, "enrichment_results_chromHMM.rds")

    writeLines(c(
        '"BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA":',
        paste0('    knowYourCG: ', as.character(packageVersion('knowYourCG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_continuous_data_sea.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ named numeric vector ] ]

    main:
    BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA.out.tables
    plots    = BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA.out.plots
    objects  = BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA.out.objects
    versions = BIOC_KNOWYOURCG_CONTINUOUS_DATA_SEA.out.versions
}
