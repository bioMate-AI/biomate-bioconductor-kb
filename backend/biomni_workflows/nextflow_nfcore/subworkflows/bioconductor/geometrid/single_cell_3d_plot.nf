#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geomeTriD — single_cell_3d_plot
// Visualize single-cell data (e.g., UMAP/t-SNE) in 3D, coloring cells by categorical or numeric metadata.
// Input: pbmc_small.3d.rds
// Container: quay.io/biocontainers/bioconductor-geometrid:1.4.1--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: geomeTriD, htmlwidgets
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load single-cell coordinate data
//  * 2. [Input & Preparation] Create 3D cell geometry objects using view3dCells
//  * 3. [Visualization & Output] Render the interactive plot using threeJsViewer

nextflow.enable.dsl = 2

process BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT {
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
    .bm_deps <- c("geomeTriD", "htmlwidgets")
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
    library(geomeTriD)
    library(htmlwidgets)
    
    # 1. Load single-cell coordinate data
    input_file <- "pbmc_small.3d.rds"
    if (!file.exists(input_file)) {
      stop(paste("Error: Required input file", input_file, "not found in the working directory."))
    }
    
    cells <- readRDS(input_file)
    
    # Print preview of the loaded data
    cat("Preview of loaded single-cell data:\n")
    print(head(cells))
    
    # 2. Create 3D cell geometry objects using view3dCells
    cellobjs <- view3dCells(cells,
      x = "umap_1", y = "umap_2", z = "umap_3",
      color = "groups",
      colorFun = function(x) {
        ifelse(x == "g1", "red", "blue")
      },
      renderer = "none"
    )
    
    # 3. Render the interactive plot using threeJsViewer
    widget <- threeJsViewer(cellobjs)
    
    # 4. Write named output files
    # Save the interactive 3D widget as an HTML file
    htmlwidgets::saveWidget(widget, file = "pbmc_small_3d_plot.html", selfcontained = TRUE)
    
    # Save the 3D geometry objects as an RDS file
    saveRDS(cellobjs, file = "pbmc_small_3d_cellobjs.rds")
    
    # Save the metadata and coordinates as a CSV file
    write.csv(cells, file = "pbmc_small_metadata.csv", row.names = TRUE)
    
    cat("Pipeline completed successfully. Outputs written:\n")
    cat("- pbmc_small_3d_plot.html (Interactive 3D visualization)\n")
    cat("- pbmc_small_3d_cellobjs.rds (3D geometry objects)\n")
    cat("- pbmc_small_metadata.csv (Metadata table)\n")

    writeLines(c(
        '"BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT":',
        paste0('    geomeTriD: ', as.character(packageVersion('geomeTriD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_3d_plot.csv versions.yml
    """
}

workflow BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc_small.3d.rds ] ]

    main:
    BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT(ch_input)

    emit:
    tables   = BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT.out.tables
    plots    = BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT.out.plots
    objects  = BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT.out.objects
    versions = BIOC_GEOMETRID_SINGLE_CELL_3D_PLOT.out.versions
}
