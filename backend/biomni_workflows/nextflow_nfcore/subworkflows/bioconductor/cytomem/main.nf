#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytoMEM — marker_enrichment_modeling_analysis
// Perform Marker Enrichment Modeling (MEM) analysis on single-cell data to generate quantitative population labels, visualize them via heatmaps, and calculate sim
// Input: cell_data.csv
// Container: quay.io/biocontainers/bioconductor-cytomem:1.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cytoMEM
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the single-cell dataset
//  * 2. [Core Analysis] Run MEM analysis using the MEM function
//  * 3. [Visualization & Output] Generate population labels and heatmaps using the build_heatmaps function
//  * 4. [Core Analysis] Calculate similarity (RMSD) scores between populations using the MEM_RMSD function

nextflow.enable.dsl = 2

process BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("cytoMEM")
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
    library(cytoMEM)
    
    # 1. Load the single-cell dataset
    # The pipeline reads cell_data.csv from the working directory.
    # This file is a single-cell expression matrix where rows are cells,
    # columns are markers, and the last column is the cluster ID.
    cell_data <- read.csv("cell_data.csv", check.names = FALSE)
    
    # 2. Run MEM analysis using the MEM function
    MEM_values <- MEM(
      cell_data,
      transform = TRUE,
      cofactor = 15,
      choose.markers = FALSE,
      markers = "all",
      choose.ref = FALSE,
      zero.ref = FALSE,
      rename.markers = FALSE,
      new.marker.names = "none",
      IQR.thresh = NULL
    )
    
    # Save the MEM values object to an RDS file
    saveRDS(MEM_values, file = "MEM_values.rds")
    
    # 3. Generate population labels and heatmaps using the build_heatmaps function
    # We wrap the heatmap generation in a PDF device to save the plots to a file.
    pdf("MEM_heatmaps.pdf", width = 10, height = 8)
    build_heatmaps(
      MEM_values,
      cluster.MEM = "both",
      cluster.medians = "none",
      cluster.IQRs = "none",
      display.thresh = 1,
      output.files = FALSE,
      labels = FALSE,
      only.MEMheatmap = FALSE
    )
    dev.off()
    
    # 4. Calculate similarity (RMSD) scores between populations using the MEM_RMSD function
    rmsd_scores <- MEM_RMSD(
      MEM_values[[5]][[1]],
      format = NULL,
      output.matrix = FALSE
    )
    
    # Save the RMSD scores to a CSV file
    write.csv(rmsd_scores, file = "MEM_RMSD_scores.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS":',
        paste0('    cytoMEM: ', as.character(packageVersion('cytoMEM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_marker_enrichment_modeling_analysis.csv versions.yml
    """
}

workflow BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cell_data.csv ] ]

    main:
    BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS.out.tables
    plots    = BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS.out.plots
    objects  = BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS.out.objects
    versions = BIOC_CYTOMEM_MARKER_ENRICHMENT_MODELING_ANALYSIS.out.versions
}
