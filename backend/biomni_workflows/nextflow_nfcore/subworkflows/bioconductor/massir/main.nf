#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: massiR — microarray_dataframe_workflow
// Predict sample sex from a normalized microarray expression data.frame using Y chromosome probes.
// Input: expression_data.csv, y_probes.csv
// Container: quay.io/biocontainers/bioconductor-massir:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: massiR
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract Y chromosome probe data and calculate CV using massi_y
//  * 2. [Visualization & Output] Plot probe variation using massi_y_plot
//  * 3. [Core Analysis] Select informative probes using massi_select
//  * 4. [Core Analysis] Predict sample sex using massi_cluster
//  * 5. [Visualization & Output] Plot clustering results using massi_cluster_plot
//  * 6. [Core Analysis] Check for sex bias using massi_dip

nextflow.enable.dsl = 2

process BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW {
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
    .bm_deps <- c("massiR")
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
    
    # Load required library
    library(massiR)
    
    # Read user input files from the working directory
    # expression_data.csv: normalized and log-transformed probe values (samples as columns, probes as rows)
    # y_probes.csv: Y chromosome probe identifiers as row names
    massi.test.dataset <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
    massi.test.probes <- read.csv("y_probes.csv", row.names = 1, check.names = FALSE)
    
    # 1. Extract Y chromosome probe data and calculate CV using massi_y
    massi.y.out <- massi_y(massi.test.dataset, massi.test.probes)
    saveRDS(massi.y.out, "massi_y_out.rds")
    
    # 2. Plot probe variation using massi_y_plot
    pdf("massi_y_plot.pdf")
    massi_y_plot(massi.y.out)
    dev.off()
    
    # 3. Select informative probes using massi_select
    massi.select.out <- 
      massi_select(massi.test.dataset, massi.test.probes, threshold=4)
    write.csv(massi.select.out, "massi_select_out.csv")
    
    # 4. Predict sample sex using massi_cluster
    results <- massi_cluster(massi.select.out)
    sample.results <- data.frame(results[[2]])
    write.csv(sample.results, "sample_results.csv", row.names = FALSE)
    saveRDS(results, "massi_cluster_results.rds")
    
    # 5. Plot clustering results using massi_cluster_plot
    pdf("massi_cluster_plot.pdf")
    massi_cluster_plot(massi.select.out, results)
    dev.off()
    
    # 6. Check for sex bias using massi_dip
    dip.result <- massi_dip(massi.select.out)
    saveRDS(dip.result, "dip_result.rds")
    
    # Save a summary of the dip test results
    dip.summary <- data.frame(
      statistic = dip.result[[1]]\$statistic,
      p_value = dip.result[[1]]\$p.value
    )
    write.csv(dip.summary, "dip_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW":',
        paste0('    massiR: ', as.character(packageVersion('massiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_dataframe_workflow.csv versions.yml
    """
}

workflow BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv, y_probes.csv ] ]

    main:
    BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW.out.tables
    plots    = BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW.out.plots
    objects  = BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW.out.objects
    versions = BIOC_MASSIR_MICROARRAY_DATAFRAME_WORKFLOW.out.versions
}
