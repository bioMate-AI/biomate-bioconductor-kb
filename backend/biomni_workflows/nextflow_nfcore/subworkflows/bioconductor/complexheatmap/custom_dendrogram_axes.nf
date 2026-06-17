#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ComplexHeatmap — custom_dendrogram_axes
// Draw a heatmap and manually add customized axes to the row and column dendrograms.
// Input: matrix
// Container: quay.io/biocontainers/bioconductor-complexheatmap:2.26.1--r45hdfd78af_0
// R packages: ComplexHeatmap
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap
// Visualizations: heatmap (ComplexHeatmap), heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Define a heatmap with custom row and column dendrogram dimensions
//  * 2. [Visualization & Output] Draw the heatmap with padding to prevent text clipping
//  * 3. [Core Analysis] Use decorate_column_dend and decorate_row_dend to add custom axes

nextflow.enable.dsl = 2

process BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ComplexHeatmap")
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
    library(ComplexHeatmap)
    library(grid)
    
    # Read the user input file 'matrix' from the working directory
    if (!file.exists("matrix")) {
      stop("Error: Input file 'matrix' not found in the working directory.")
    }
    
    # Robustly read the matrix, preserving row and column names if present
    m = tryCatch({
      as.matrix(read.table("matrix", header = TRUE, row.names = 1, check.names = FALSE))
    }, error = function(e) {
      as.matrix(read.table("matrix", header = FALSE))
    })
    
    # Ensure the matrix is numeric
    m_dims = dimnames(m)
    m = matrix(as.numeric(m), nrow = nrow(m), ncol = ncol(m))
    dimnames(m) = m_dims
    
    # Open a PDF device to save the final decorated heatmap
    pdf("heatmap_custom_axes.pdf", width = 8, height = 8)
    
    # 1. Define a heatmap with custom row and column dendrogram dimensions
    ht = Heatmap(m, name = "foo", 
    	row_dend_width = unit(4, "cm"),
    	column_dend_height = unit(4, "cm")
    )
    
    # 2. Draw the heatmap with padding to prevent text clipping
    draw(ht, padding = unit(c(15, 2, 2, 2), "mm"))
    
    # 3. Use decorate_column_dend and decorate_row_dend to add custom axes
    decorate_column_dend("foo", {
    	grid.yaxis()
    })
    
    decorate_row_dend("foo", {
    	vp = current.viewport()
    	xscale = vp\$xscale
    	grid.xaxis(at = xscale[2] - 0:5, label = 0:5)
    })
    
    # Close the plotting device
    dev.off()

    writeLines(c(
        '"BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES":',
        paste0('    ComplexHeatmap: ', as.character(packageVersion('ComplexHeatmap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_dendrogram_axes.csv versions.yml
    """
}

workflow BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix ] ]

    main:
    BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES(ch_input)

    emit:
    tables   = BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES.out.tables
    plots    = BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES.out.plots
    objects  = BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES.out.objects
    versions = BIOC_COMPLEXHEATMAP_CUSTOM_DENDROGRAM_AXES.out.versions
}
