#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geva — quick_analysis
// Perform a rapid, automated GEVA analysis using the shortcut function geva.quick to run all intermediate steps at once.
// Input: ginput
// Container: quay.io/biocontainers/bioconductor-geva:1.18.0--r45hdfd78af_0
// Requires: geva
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the entire pipeline in a single call
//  * 2. [Core Analysis] Re-analyze with different parameters

nextflow.enable.dsl = 2

process BIOC_GEVA_QUICK_ANALYSIS {
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
    .bm_deps <- c("geva")
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
    library(geva)
    
    # 1. Read User Input
    # The pipeline expects 'ginput.rds' in the working directory containing a GEVAInput object.
    input_file <- "ginput.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    ginput <- readRDS(input_file)
    
    # Ensure the input is of the correct class
    if (!inherits(ginput, "GEVAInput")) {
      stop("Error: The input object must be of class 'GEVAInput'.")
    }
    
    # 2. Execute Documented Workflow Steps
    
    # Step 2.1: Run geva.quick with resolution = 0.25
    message("Running geva.quick with resolution = 0.25...")
    gresults <- geva.quick(ginput, resolution=0.25)
    
    # Save intermediate results for resolution 0.25
    write.csv(results.table(gresults), "gresults_resolution_0.25_table.csv", row.names = TRUE)
    pdf("gresults_resolution_0.25_plot.pdf", width = 9, height = 6)
    plot(gresults)
    dev.off()
    
    # Step 2.2: Run geva.quick with resolution = 0.4
    message("Running geva.quick with resolution = 0.4...")
    gresults <- geva.quick(ginput, resolution=0.4)
    
    # Save intermediate results for resolution 0.4
    write.csv(results.table(gresults), "gresults_resolution_0.4_table.csv", row.names = TRUE)
    pdf("gresults_resolution_0.4_plot.pdf", width = 9, height = 6)
    plot(gresults)
    dev.off()
    
    # Step 2.3: Run geva.quick with summary.method = 'mean'
    message("Running geva.quick with summary.method = 'mean'...")
    gresults <- geva.quick(ginput, summary.method='mean')
    
    # Save intermediate results for summary.method = 'mean'
    write.csv(results.table(gresults), "gresults_mean_table.csv", row.names = TRUE)
    pdf("gresults_mean_plot.pdf", width = 9, height = 6)
    plot(gresults)
    dev.off()
    
    # Step 2.4: Re-analyze the results using summary.method = 'median'
    message("Re-analyzing results with summary.method = 'median'...")
    gresults <- geva.quick(gresults, summary.method='median')
    
    # Save final results
    write.csv(results.table(gresults), "gresults_final_table.csv", row.names = TRUE)
    
    # Extract and save top genes if available
    tryCatch({
      top_genes_df <- top.genes(gresults)
      write.csv(top_genes_df, "top_genes_final.csv", row.names = TRUE)
    }, error = function(e) {
      message("Warning: Could not extract top genes. ", e\$message)
    })
    
    # Save final plot
    pdf("gresults_final_plot.pdf", width = 9, height = 6)
    plot(gresults)
    dev.off()
    
    # Save final RDS object
    saveRDS(gresults, "gresults_final.rds")
    
    message("GEVA quick analysis pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GEVA_QUICK_ANALYSIS":',
        paste0('    geva: ', as.character(packageVersion('geva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_analysis.csv versions.yml
    """
}

workflow BIOC_GEVA_QUICK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ginput ] ]

    main:
    BIOC_GEVA_QUICK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEVA_QUICK_ANALYSIS.out.tables
    plots    = BIOC_GEVA_QUICK_ANALYSIS.out.plots
    objects  = BIOC_GEVA_QUICK_ANALYSIS.out.objects
    versions = BIOC_GEVA_QUICK_ANALYSIS.out.versions
}
