#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ComplexHeatmap — annotations_only
// Visualize dendrograms and multiple annotations without displaying a main heatmap body.
// Input: matrix
// Container: quay.io/biocontainers/bioconductor-complexheatmap:2.26.1--r45hdfd78af_0
// R packages: ComplexHeatmap
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap
// Visualizations: heatmap (ComplexHeatmap), heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute hierarchical clustering on the input matrix
//  * 2. [Visualization & Output] Create a zero-column matrix to act as the heatmap body
//  * 3. [Visualization & Output] Draw the heatmap with the zero-column matrix, the computed dendrogram, and row annotations

nextflow.enable.dsl = 2

process BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    
    # Load required library
    library(ComplexHeatmap)
    
    # 1. Read the user input matrix from the working directory
    # Assuming 'matrix' is a standard space/tab-delimited numeric matrix file
    input_matrix <- as.matrix(read.table("matrix", header = FALSE))
    N <- nrow(input_matrix)
    
    # 2. Compute hierarchical clustering on the input matrix
    hc = hclust(dist(input_matrix))
    
    # 3. Create the heatmap with a zero-column matrix, the computed dendrogram, and row annotations
    ht = Heatmap(matrix(nc = 0, nr = N), cluster_rows = hc, 
    	right_annotation = rowAnnotation(
    		foo = anno_points(1:N),
    		sth = 1:N,
    		bar = anno_barplot(1:N)),
    	row_split = 2)
    
    # 4. Save the outputs (PDF plot and RDS object)
    pdf("annotations_only_heatmap.pdf", width = 8, height = 8)
    draw(ht)
    dev.off()
    
    saveRDS(ht, "heatmap_object.rds")

    writeLines(c(
        '"BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY":',
        paste0('    ComplexHeatmap: ', as.character(packageVersion('ComplexHeatmap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotations_only.csv versions.yml
    """
}

workflow BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix ] ]

    main:
    BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY(ch_input)

    emit:
    tables   = BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY.out.tables
    plots    = BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY.out.plots
    objects  = BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY.out.objects
    versions = BIOC_COMPLEXHEATMAP_ANNOTATIONS_ONLY.out.versions
}
