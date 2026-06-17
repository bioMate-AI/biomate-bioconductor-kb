#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ComplexHeatmap — group_level_clustering
// Group rows into several clusters and make a group-level dendrogram to simplify visualization of large matrices.
// Input: matrix
// Container: quay.io/biocontainers/bioconductor-complexheatmap:2.26.1--r45hdfd78af_0
// R packages: ComplexHeatmap, markdown
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap
// Visualizations: heatmap (ComplexHeatmap), heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform hierarchical clustering on the matrix
//  * 2. [Core Analysis] Cut the dendrogram into a specified number of groups
//  * 3. [Visualization & Output] Generate a heatmap using cluster_within_group and split rows

nextflow.enable.dsl = 2

process BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING {
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
    .bm_deps <- c("ComplexHeatmap", "markdown")
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
    library(ComplexHeatmap)
    
    # 1. Read the user input file 'matrix'
    if (!file.exists("matrix")) {
      stop("Error: Input file 'matrix' not found in the working directory.")
    }
    
    # Attempt to read the matrix robustly
    m <- tryCatch({
      # Try reading as RDS
      readRDS("matrix")
    }, error = function(e) {
      # Try reading as a table (CSV/TSV/txt)
      tryCatch({
        as.matrix(read.table("matrix", header = TRUE, row.names = 1, sep = "", check.names = FALSE))
      }, error = function(e2) {
        tryCatch({
          as.matrix(read.csv("matrix", header = TRUE, row.names = 1, check.names = FALSE))
        }, error = function(e3) {
          # Fallback to basic read.table
          as.matrix(read.table("matrix", header = TRUE, check.names = FALSE))
        })
      })
    })
    
    # Ensure the matrix is numeric
    m <- as.matrix(m)
    mode(m) <- "numeric"
    
    # 2. Perform hierarchical clustering on the matrix
    hc = hclust(dist(m))
    
    # 3. Cut the dendrogram into a specified number of groups
    group = cutree(hc, k = 6)
    
    # 4. Generate a heatmap using cluster_within_group and split rows, and save to PDF
    pdf("heatmap_group_level_clustering.pdf", width = 8, height = 10)
    ht = Heatmap(m, cluster_rows = cluster_within_group(t(m), group), 
    	row_split = 6, border = TRUE)
    draw(ht)
    dev.off()
    
    # 5. Save meaningful outputs
    row_names <- rownames(m)
    if (is.null(row_names)) {
      row_names <- seq_len(nrow(m))
    }
    
    group_df <- data.frame(
      RowName = row_names,
      Group = group
    )
    
    write.csv(group_df, "group_assignments.csv", row.names = FALSE)
    saveRDS(hc, "hclust_model.rds")
    saveRDS(ht, "heatmap_object.rds")

    writeLines(c(
        '"BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING":',
        paste0('    ComplexHeatmap: ', as.character(packageVersion('ComplexHeatmap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_group_level_clustering.csv versions.yml
    """
}

workflow BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ matrix ] ]

    main:
    BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING.out.tables
    plots    = BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING.out.plots
    objects  = BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING.out.objects
    versions = BIOC_COMPLEXHEATMAP_GROUP_LEVEL_CLUSTERING.out.versions
}
