#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: openCyto — interactive_gating
// Interactively add and remove gating methods on a GatingSet without using a CSV template.
// Input: gs
// Container: quay.io/biocontainers/bioconductor-opencyto:2.22.0--r45ha27e39d_0
// Requires: flowWorkspace, openCyto
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Add a gating method to the GatingSet
//  * 2. [Core Analysis] Remove the last added gating method to undo the operation

nextflow.enable.dsl = 2

process BIOC_OPENCYTO_INTERACTIVE_GATING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("flowWorkspace", "openCyto")
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
    library(openCyto)
    library(flowWorkspace)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input
    # -----------------------------------------------------------------------------
    # The pipeline expects an existing, compensated, and transformed GatingSet 
    # named 'gs' in the working directory. It can be either a directory (saved via 
    # save_gs) or a serialized RDS file.
    if (dir.exists("gs")) {
      message("Loading GatingSet from directory 'gs'...")
      gs <- load_gs("gs")
    } else if (file.exists("gs")) {
      message("Loading GatingSet from file 'gs'...")
      gs <- readRDS("gs")
    } else {
      stop("Error: Input 'gs' (GatingSet) not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # Stage 1: Add a gating method to the GatingSet
    # -----------------------------------------------------------------------------
    # Dynamically determine a valid parent node and dimensions from the provided GatingSet
    nodes <- gs_get_pop_paths(gs)
    parent_node <- nodes[length(nodes)]
    channels <- colnames(gs)
    dims_str <- paste(channels[1:2], collapse = ",")
    
    message("Adding gating method 'dummy_gate'...")
    gs_add_gating_method(gs, alias = "dummy_gate",
                             pop = "--",
                             parent = parent_node,
                             dims = dims_str,
                             gating_method = "mindensity")
    
    # Save visualization of the gating hierarchy after adding the method
    pdf("gating_hierarchy_added.pdf")
    if (length(gs) > 0) {
      plot(gs[[1]])
    }
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 2: Remove the last added gating method to undo the operation
    # -----------------------------------------------------------------------------
    message("Removing the last added gating method...")
    gs_remove_gating_method(gs)
    
    # Save visualization of the gating hierarchy after removing the method
    pdf("gating_hierarchy_removed.pdf")
    if (length(gs) > 0) {
      plot(gs[[1]])
    }
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 3: Save Outputs
    # -----------------------------------------------------------------------------
    message("Saving the final GatingSet...")
    output_path <- "gs_interactive_output"
    if (dir.exists(output_path)) {
      unlink(output_path, recursive = TRUE)
    }
    save_gs(gs, path = output_path)
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_OPENCYTO_INTERACTIVE_GATING":',
        paste0('    openCyto: ', as.character(packageVersion('openCyto')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_gating.csv versions.yml
    """
}

workflow BIOC_OPENCYTO_INTERACTIVE_GATING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gs ] ]

    main:
    BIOC_OPENCYTO_INTERACTIVE_GATING(ch_input)

    emit:
    tables   = BIOC_OPENCYTO_INTERACTIVE_GATING.out.tables
    plots    = BIOC_OPENCYTO_INTERACTIVE_GATING.out.plots
    objects  = BIOC_OPENCYTO_INTERACTIVE_GATING.out.objects
    versions = BIOC_OPENCYTO_INTERACTIVE_GATING.out.versions
}
