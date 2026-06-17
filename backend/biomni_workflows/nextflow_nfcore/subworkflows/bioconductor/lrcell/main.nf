#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LRcell — lrcell_preloaded_markers
// Run cell-type enrichment analysis on bulk RNA-seq differential expression results using pre-loaded marker genes from ExperimentHub.
// Input: example_gene_pvals.RData
// Container: quay.io/biocontainers/bioconductor-lrcell:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: LRcell
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load bulk DE p-values
//  * 2. [Core Analysis] Run LRcell using linear regression with specified species and brain region
//  * 3. [Visualization & Output] Exclude leading genes for clean visualization
//  * 4. [Visualization & Output] Plot the enrichment results using a Manhattan plot

nextflow.enable.dsl = 2

process BIOC_LRCELL_LRCELL_PRELOADED_MARKERS {
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
    .bm_deps <- c("LRcell")
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
        library(LRcell)
        
        # 1. Load bulk DE p-values from the user-provided RData file
        if (!file.exists("example_gene_pvals.RData")) {
          stop("Error: Input file 'example_gene_pvals.RData' not found in the working directory.")
        }
        
        # Load the RData file which contains the 'example_gene_pvals' object
        load("example_gene_pvals.RData")
        
        # Verify that the expected object is loaded
        if (!exists("example_gene_pvals")) {
          # If the object inside has a different name, attempt to find it
          loaded_objects <- ls()
          loaded_objects <- loaded_objects[loaded_objects != "loaded_objects"]
          if (length(loaded_objects) > 0) {
            example_gene_pvals <- get(loaded_objects[1])
          } else {
            stop("Error: No objects found in 'example_gene_pvals.RData'.")
          }
        }
        
        # Ensure it is a named numeric vector
        if (!is.numeric(example_gene_pvals) || is.null(names(example_gene_pvals))) {
          stop("Error: Loaded object must be a named numeric vector of p-values.")
        }
        
        # 2. Run LRcell using linear regression with specified species and brain region
        res <- LRcell(gene.p = example_gene_pvals,
                      marker.g = NULL,
                      species = "mouse",
                      region = "FC",
                      method = "LiR")
        
        FC_res <- res\$FC
        
        # Save the raw results object
        saveRDS(res, "LRcell_raw_results.rds")
        
        # 3. Exclude leading genes for clean visualization and export table
        sub_FC_res <- subset(FC_res, select=-lead_genes)
        write.csv(sub_FC_res, "LRcell_FC_results_no_lead_genes.csv", row.names = FALSE)
        
        # Print the head of the cleaned results to console
        cat("Head of LRcell Frontal Cortex enrichment results (excluding leading genes):\n")
        print(head(sub_FC_res))
        
        # 4. Plot the enrichment results using a Manhattan plot and save to PDF
        pdf("LRcell_manhattan_enrichment_plot.pdf", width = 10, height = 6)
        print(plot_manhattan_enrich(FC_res, sig.cutoff = .05, label.topn = 5))
        dev.off()
        
        cat("\nPipeline completed successfully. Outputs written:\n")
        cat("- 'LRcell_raw_results.rds' (Full results object)\n")
        cat("- 'LRcell_FC_results_no_lead_genes.csv' (Enrichment table without lead genes column)\n")
        cat("- 'LRcell_manhattan_enrichment_plot.pdf' (Manhattan plot of enrichment results)\n")

    writeLines(c(
        '"BIOC_LRCELL_LRCELL_PRELOADED_MARKERS":',
        paste0('    LRcell: ', as.character(packageVersion('LRcell')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lrcell_preloaded_markers.csv versions.yml
    """
}

workflow BIOC_LRCELL_LRCELL_PRELOADED_MARKERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_gene_pvals.RData ] ]

    main:
    BIOC_LRCELL_LRCELL_PRELOADED_MARKERS(ch_input)

    emit:
    tables   = BIOC_LRCELL_LRCELL_PRELOADED_MARKERS.out.tables
    plots    = BIOC_LRCELL_LRCELL_PRELOADED_MARKERS.out.plots
    objects  = BIOC_LRCELL_LRCELL_PRELOADED_MARKERS.out.objects
    versions = BIOC_LRCELL_LRCELL_PRELOADED_MARKERS.out.versions
}
