#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SingleR — annotation_with_builtin_reference
// Annotate single-cell RNA-seq test data using a built-in reference dataset from the celldex package.
// Input: test_dataset.rds, reference_dataset.rds
// Container: quay.io/biocontainers/bioconductor-singler:2.12.0--r45ha27e39d_0
// R packages: SummarizedExperiment, BiocStyle, celldex, scRNAseq, scuttle, SingleR
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleR, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the built-in reference dataset
//  * 2. [Input & Preparation] Load the test dataset
//  * 3. [Core Analysis] Run SingleR annotation using the reference labels
//  * 4. [Visualization & Output] Summarize the predicted labels

nextflow.enable.dsl = 2

process BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE {
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
    .bm_deps <- c("SummarizedExperiment", "BiocStyle", "celldex", "scRNAseq", "scuttle", "SingleR")
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
    library(SingleR)
    
    # 1. Load the built-in reference dataset from user input
    hpca.se <- readRDS("reference_dataset.rds")
    
    # 2. Load the test dataset from user input
    hESCs <- readRDS("test_dataset.rds")
    
    # 3. Run SingleR annotation using the reference labels
    pred.hesc <- SingleR(test = hESCs, ref = hpca.se, assay.type.test=1, labels = hpca.se\$label.main)
    
    # 4. Summarize the predicted labels
    label_summary <- table(pred.hesc\$labels)
    print(label_summary)
    
    # Write outputs to files
    saveRDS(pred.hesc, "predicted_labels.rds")
    
    # Save summary table as CSV
    summary_df <- as.data.frame(label_summary)
    colnames(summary_df) <- c("Cell_Type", "Count")
    write.csv(summary_df, "predicted_labels_summary.csv", row.names = FALSE)
    
    # Save detailed predictions as CSV
    pred_df <- as.data.frame(pred.hesc)
    write.csv(pred_df, "predictions_detailed.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE":',
        paste0('    SingleR: ', as.character(packageVersion('SingleR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotation_with_builtin_reference.csv versions.yml
    """
}

workflow BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test_dataset.rds, reference_dataset.rds ] ]

    main:
    BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE(ch_input)

    emit:
    tables   = BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE.out.tables
    plots    = BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE.out.plots
    objects  = BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE.out.objects
    versions = BIOC_SINGLER_ANNOTATION_WITH_BUILTIN_REFERENCE.out.versions
}
