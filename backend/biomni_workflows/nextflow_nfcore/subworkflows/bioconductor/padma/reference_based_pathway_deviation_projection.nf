#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: padma — reference_based_pathway_deviation_projection
// Perform Multiple Factor Analysis on a reference population and project supplementary individuals onto the reference consensus to calculate their pathway deviati
// Input: mae
// Container: quay.io/biocontainers/bioconductor-padma:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, ggplot2, padma
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read the input MultiAssayExperiment object from the
//  * 2. [Input & Preparation] Define the pathway name
//  * 3. [Input & Preparation] Run padma with base_ids and supp_ids specified (exactly
//  * 4. [Input & Preparation] Save the results to output files

nextflow.enable.dsl = 2

process BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(padma)
    library(MultiAssayExperiment)
    library(ggplot2)
    
    # --- Read the input MultiAssayExperiment object from the ---
    mae <- readRDS("mae.rds")
    
    # --- Define the pathway name ---
    D4GDI <- "c2_cp_BIOCARTA_D4GDI_PATHWAY"
    
    # Safely determine base_ids and supp_ids to avoid out-of-bounds and duplicates
    unique_samples <- unique(sampleMap(mae)\$primary)
    n_samples <- length(unique_samples)
    
    if (n_samples >= 20) {
      base_samples <- unique_samples[1:10]
      supp_samples <- unique_samples[15:20]
    } else {
      mid <- max(1, floor(n_samples / 2))
      base_samples <- unique_samples[1:mid]
      if (n_samples > 1) {
        supp_samples <- unique_samples[(mid + 1):n_samples]
      } else {
        supp_samples <- NULL
      }
    }
    
    # --- Run padma with base_ids and supp_ids specified (exactly ---
    run_padma_supp <- 
      padma(mae, pathway_name = D4GDI, verbose = FALSE,
            base_ids = base_samples,
            supp_ids = supp_samples)
    
    # --- Save the results to output files ---
    saveRDS(run_padma_supp, "run_padma_supp.rds")
    
    # Export pathway deviation scores
    pathway_scores <- assay(run_padma_supp)
    write.csv(pathway_scores, "pathway_deviation_scores.csv", row.names = TRUE)
    
    # Export gene-specific deviation scores
    gene_scores <- pathway_gene_deviation(run_padma_supp)
    write.csv(gene_scores, "gene_deviation_scores.csv", row.names = TRUE)
    
    # Generate and save factor map plot
    pdf("factor_map.pdf", width = 7, height = 6)
    tryCatch({
      print(factorMap(run_padma_supp))
    }, error = function(e) {
      warning("Could not generate factorMap: ", e\$message)
    })
    dev.off()
    
    # Generate and save omics contribution plot
    pdf("omics_contribution.pdf", width = 7, height = 6)
    tryCatch({
      print(omicsContrib(run_padma_supp))
    }, error = function(e) {
      warning("Could not generate omicsContrib: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION":',
        paste0('    padma: ', as.character(packageVersion('padma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_based_pathway_deviation_projection.csv versions.yml
    """
}

workflow BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mae ] ]

    main:
    BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION(ch_input)

    emit:
    tables   = BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION.out.tables
    plots    = BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION.out.plots
    objects  = BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION.out.objects
    versions = BIOC_PADMA_REFERENCE_BASED_PATHWAY_DEVIATION_PROJECTION.out.versions
}
