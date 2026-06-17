#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miRLAB — top_interactions_validation
// Predict miRNA targets and extract/validate the overall top predicted interactions across multiple miRNAs.
// Input: ToyEMT.csv, Toygroundtruth.csv
// Container: quay.io/biocontainers/bioconductor-mirlab:1.40.0--r45hdfd78af_0
// R packages: miRLAB
// Bioconductor: 3.20 | R: 4.4
// Requires: miRLAB
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Predict miRNA targets using Pearson correlation
//  * 2. [Core Analysis] Extract the top overall interactions using Extopk
//  * 3. [Core Analysis] Validate the top interactions against ground truth using Validation

nextflow.enable.dsl = 2

process BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION {
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
    .bm_deps <- c("miRLAB")
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
    
    # Load the required library
    library(miRLAB)
    
    # Define the input files in the working directory
    dataset <- "ToyEMT.csv"
    groundtruth <- "Toygroundtruth.csv"
    
    # 1. Predict miRNA targets using Pearson correlation
    # Columns 1:3 are miRNAs (cause), columns 4:18 are mRNAs (effect)
    EMTresults <- Pearson(dataset, 1:3, 4:18)
    
    # 2. Extract the top 10 overall interactions
    top10 <- Extopk(EMTresults, 10)
    
    # 3. Validate the top interactions against ground truth
    top10Confirmed <- Validation(top10, groundtruth)
    
    # Save the results to output files
    write.csv(EMTresults, "EMTresults_pearson.csv", row.names = TRUE)
    write.csv(top10, "top10_interactions.csv", row.names = FALSE)
    write.csv(top10Confirmed, "top10_confirmed_interactions.csv", row.names = FALSE)
    saveRDS(top10Confirmed, "top10Confirmed.rds")
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION":',
        paste0('    miRLAB: ', as.character(packageVersion('miRLAB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_top_interactions_validation.csv versions.yml
    """
}

workflow BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyEMT.csv, Toygroundtruth.csv ] ]

    main:
    BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION(ch_input)

    emit:
    tables   = BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION.out.tables
    plots    = BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION.out.plots
    objects  = BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION.out.objects
    versions = BIOC_MIRLAB_TOP_INTERACTIONS_VALIDATION.out.versions
}
