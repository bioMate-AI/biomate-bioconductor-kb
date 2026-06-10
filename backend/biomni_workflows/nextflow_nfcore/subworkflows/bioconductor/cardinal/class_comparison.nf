#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cardinal — class_comparison
// Perform statistical hypothesis testing to identify differentially abundant mass features between experimental conditions.
// Input: experimental_msi.rds
// Container: quay.io/biocontainers/bioconductor-cardinal:3.12.1--r45hdfd78af_0
// Requires: Cardinal
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform sample-based means testing using meansTest
//  * 2. [Core Analysis] Perform segment-based means testing by first segmenting with spatialDGMM and then testing with meansTest

nextflow.enable.dsl = 2

process BIOC_CARDINAL_CLASS_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("Cardinal")
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
    library(Cardinal)
    
    # Read the user input file
    mse3 <- readRDS("experimental_msi.rds")
    
    # Stage 1: Sample-based means testing using meansTest
    mtest <- meansTest(mse3, ~ condition, samples=run(mse3))
    
    # Save the plot for sample-based means testing
    pdf("meansTest_plots.pdf", width=12, height=6)
    plot(mtest, i=1:10, layout=c(2,5), ylab="Intensity", fill=TRUE)
    dev.off()
    
    # Extract and save top features
    mtest_top <- topFeatures(mtest)
    write.csv(as.data.frame(mtest_top), "meansTest_top_features.csv", row.names=FALSE)
    saveRDS(mtest, "meansTest_result.rds")
    
    # Stage 2: Segment-based means testing
    # First segment with spatialDGMM
    dgmm2 <- spatialDGMM(mse3, r=2, k=2, groups=run(mse3))
    saveRDS(dgmm2, "spatialDGMM_result.rds")
    
    # Then test with meansTest
    stest <- meansTest(dgmm2, ~ condition)
    
    # Save the plot for segment-based means testing
    pdf("segment_meansTest_plots.pdf", width=12, height=6)
    plot(stest, i=1:10, layout=c(2,5), ylab="Intensity", fill=TRUE)
    dev.off()
    
    # Extract and save top features
    stest_top <- topFeatures(stest)
    write.csv(as.data.frame(stest_top), "segment_meansTest_top_features.csv", row.names=FALSE)
    saveRDS(stest, "segment_meansTest_result.rds")

    writeLines(c(
        '"BIOC_CARDINAL_CLASS_COMPARISON":',
        paste0('    Cardinal: ', as.character(packageVersion('Cardinal')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_class_comparison.csv versions.yml
    """
}

workflow BIOC_CARDINAL_CLASS_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ experimental_msi.rds ] ]

    main:
    BIOC_CARDINAL_CLASS_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CARDINAL_CLASS_COMPARISON.out.tables
    plots    = BIOC_CARDINAL_CLASS_COMPARISON.out.plots
    objects  = BIOC_CARDINAL_CLASS_COMPARISON.out.objects
    versions = BIOC_CARDINAL_CLASS_COMPARISON.out.versions
}
