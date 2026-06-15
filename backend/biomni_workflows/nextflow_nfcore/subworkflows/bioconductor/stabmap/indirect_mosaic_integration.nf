#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: StabMap — indirect_mosaic_integration
// Integrate three or more single-cell datasets where some pairs share no features (e.g., RNA and ATAC) but are connected via an intermediate dataset (e.g., Multio
// Input: assay_list_indirect
// Container: quay.io/biocontainers/bioconductor-stabmap:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: StabMap
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Inspect shared features using mosaicDataUpSet
//  * 2. [Visualization & Output] Build and plot the indirect mosaic data topology using mosaicDataTopology
//  * 3. [Core Analysis] Generate a joint embedding using stabMap

nextflow.enable.dsl = 2

process BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION {
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
    .bm_deps <- c("StabMap")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
    library(StabMap)
    
    # -----------------------------------------------------------------------------
    # Input Loading
    # -----------------------------------------------------------------------------
    # The pipeline expects 'assay_list_indirect' as an RDS file in the working directory.
    input_file <- "assay_list_indirect.rds"
    if (!file.exists(input_file)) {
      if (file.exists("assay_list_indirect")) {
        input_file <- "assay_list_indirect"
      } else {
        stop("Required input file 'assay_list_indirect.rds' or 'assay_list_indirect' not found in the working directory.")
      }
    }
    
    assay_list_indirect <- readRDS(input_file)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Inspect shared features using mosaicDataUpSet
    # -----------------------------------------------------------------------------
    upset_res <- mosaicDataUpSet(assay_list_indirect, plot = FALSE)
    saveRDS(upset_res, "mosaic_upset_results.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 2: Build and plot the indirect mosaic data topology
    # -----------------------------------------------------------------------------
    mdt_indirect <- mosaicDataTopology(assay_list_indirect)
    saveRDS(mdt_indirect, "mdt_indirect.rds")
    
    # Save the topology plot to a PDF file
    pdf("mdt_indirect_plot.pdf", width = 7, height = 7)
    plot(mdt_indirect)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 3: Generate a joint embedding using stabMap
    # -----------------------------------------------------------------------------
    stab_indirect <- stabMap(assay_list_indirect,
      reference_list = c("Multiome"),
      plot = FALSE
    )
    
    # Save the joint embedding results
    saveRDS(stab_indirect, "stab_indirect.rds")
    write.csv(as.matrix(stab_indirect), "stab_indirect.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION":',
        paste0('    StabMap: ', as.character(packageVersion('StabMap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_indirect_mosaic_integration.csv versions.yml
    """
}

workflow BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ assay_list_indirect ] ]

    main:
    BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION.out.tables
    plots    = BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION.out.plots
    objects  = BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION.out.objects
    versions = BIOC_STABMAP_INDIRECT_MOSAIC_INTEGRATION.out.versions
}
