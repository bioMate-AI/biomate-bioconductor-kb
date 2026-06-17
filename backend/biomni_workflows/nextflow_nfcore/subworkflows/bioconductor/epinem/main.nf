#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epiNEM — small_gene_set_inference
// Infer the epistatic network structure and logical gates for a small set of signaling genes.
// Input: binary_effects_matrix.csv
// Container: quay.io/biocontainers/bioconductor-epinem:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: epiNEM
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare binary effect matrix
//  * 2. [Core Analysis] Run epiNEM network inference
//  * 3. [Visualization & Output] Plot the inferred network structure

nextflow.enable.dsl = 2

process BIOC_EPINEM_SMALL_GENE_SET_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("epiNEM")
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
    library(epiNEM)
    
    # 1. Prepare binary effect matrix
    # Read the user-provided binary effects matrix from the working directory
    input_file <- "binary_effects_matrix.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    raw_data <- read.csv(input_file, row.names = 1, check.names = FALSE)
    data <- as.matrix(raw_data)
    
    # Print head of the data as in the documented workflow
    print(head(data))
    
    # 2. Run epiNEM network inference
    # Keep the exact function call and arguments from the documented code
    res <- epiNEM(data, method = "exhaustive")
    
    # 3. Plot the inferred network structure and save outputs
    # Save the plot to a PDF file
    pdf("epinem_network.pdf", width = 7, height = 7)
    plot(res)
    dev.off()
    
    # Save the complete result object as an RDS file
    saveRDS(res, "epinem_result.rds")
    
    # Export meaningful tabular results if available in the output object
    tryCatch({
      if (!is.null(res\$results)) {
        # Export the inferred adjacency matrix of the signaling genes
        if (!is.null(res\$results\$model)) {
          write.csv(as.matrix(res\$results\$model), "inferred_adjacency_matrix.csv", row.names = TRUE)
        }
        # Export the logic gates assigned to the signaling gene triples/pairs
        if (!is.null(res\$results\$logic)) {
          write.csv(as.data.frame(res\$results\$logic), "inferred_logic_gates.csv", row.names = TRUE)
        }
        # Export the attachment of effect reporters to the signaling genes
        if (!is.null(res\$results\$attachment)) {
          write.csv(as.data.frame(res\$results\$attachment), "reporter_attachments.csv", row.names = TRUE)
        }
      }
    }, error = function(e) {
      warning("Could not export all detailed tabular results: ", e\$message)
    })
    
    cat("Pipeline completed successfully. Outputs saved: epinem_network.pdf, epinem_result.rds, and associated CSV tables.\n")

    writeLines(c(
        '"BIOC_EPINEM_SMALL_GENE_SET_INFERENCE":',
        paste0('    epiNEM: ', as.character(packageVersion('epiNEM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_small_gene_set_inference.csv versions.yml
    """
}

workflow BIOC_EPINEM_SMALL_GENE_SET_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ binary_effects_matrix.csv ] ]

    main:
    BIOC_EPINEM_SMALL_GENE_SET_INFERENCE(ch_input)

    emit:
    tables   = BIOC_EPINEM_SMALL_GENE_SET_INFERENCE.out.tables
    plots    = BIOC_EPINEM_SMALL_GENE_SET_INFERENCE.out.plots
    objects  = BIOC_EPINEM_SMALL_GENE_SET_INFERENCE.out.objects
    versions = BIOC_EPINEM_SMALL_GENE_SET_INFERENCE.out.versions
}
