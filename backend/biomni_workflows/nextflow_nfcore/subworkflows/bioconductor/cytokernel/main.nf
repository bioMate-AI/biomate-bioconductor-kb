#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cytoKernel — differential_expression_analysis
// Identify differentially expressed features in high-dimensional biological data using a kernel-based score test, filter the dataset, and visualize the top result
// Input: expression_matrix.csv, group_labels.csv
// Container: quay.io/biocontainers/bioconductor-cytokernel:1.16.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, SummarizedExperiment, cytoKernel
// Visualizations: heatmap (ComplexHeatmap), heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run the kernel-based score test using CytoK()
//  * 2. [Core Analysis] Extract all features, ordered features, and percentage of DE features using CytoKFeatures(), CytoKFeaturesOrdered(), and CytoKDEfe
//  * 3. [Core Analysis] Filter the original dataset to retain only differentially expressed features using CytoKDEData()
//  * 4. [Visualization & Output] Visualize the top differentially expressed features using plotCytoK() and ComplexHeatmap

nextflow.enable.dsl = 2

process BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS {
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
    .bm_deps <- c("cytoKernel", "ComplexHeatmap", "SummarizedExperiment")
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
    library(SummarizedExperiment)
    library(cytoKernel)
    library(ComplexHeatmap)
    
    # 1. Read User Input Files
    # Read expression matrix (features on rows, samples on columns)
    expr_mat <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Read group labels (binary categorical vector: 0 and 1)
    group_data <- read.csv("group_labels.csv", header = FALSE)
    if (!is.numeric(group_data[1, 1])) {
      group_data <- read.csv("group_labels.csv", header = TRUE)
    }
    group_factor_vector <- as.numeric(group_data[[1]])
    
    # Construct SummarizedExperiment object
    # The package expects a 'cluster' column in rowData for feature identification
    row_data <- data.frame(cluster = rownames(expr_mat), row.names = rownames(expr_mat))
    cyto_data <- SummarizedExperiment(
      assays = list(exprs = expr_mat),
      rowData = row_data
    )
    
    # 2. Run the kernel-based score test using CytoK()
    CytoK_output <- CytoK(
      cyto_data,
      group_factor = group_factor_vector,
      lowerRho = 2,
      upperRho = 12,
      gridRho = 4,
      alpha = 0.05,
      featureVars = NULL
    )
    
    # Print output summary to console
    print(CytoK_output)
    
    # 3. Extract features, ordered features, and percentage of DE features
    features_df <- CytoKFeatures(CytoK_output)
    features_ordered_df <- CytoKFeaturesOrdered(CytoK_output)
    de_percent <- CytoKDEfeatures(CytoK_output)
    
    # Print heads to console
    print(head(features_df))
    print(head(features_ordered_df))
    print(de_percent)
    
    # Write extracted features to output files
    write.csv(features_df, "cytoK_features.csv", row.names = TRUE)
    write.csv(features_ordered_df, "cytoK_features_ordered.csv", row.names = TRUE)
    write(de_percent, "cytoK_de_percent.txt")
    
    # 4. Filter the original dataset to retain only differentially expressed features
    CytoKDEData_HD <- CytoKDEData(CytoK_output, by = "features")
    print(CytoKDEData_HD)
    
    # Save filtered dataset
    saveRDS(CytoKDEData_HD, "cytoK_de_data.rds")
    write.csv(as.data.frame(assay(CytoKDEData_HD)), "cytoK_de_expression.csv", row.names = TRUE)
    
    # 5. Visualize the top differentially expressed features
    topK <- min(10, nrow(features_ordered_df))
    
    heatmap1 <- plotCytoK(
      CytoK_output,
      group_factor = group_factor_vector,
      topK = topK,
      featureVars = NULL
    )
    
    featureOrderedExtracted <- CytoKFeaturesOrdered(CytoK_output)
    rowmeta_cluster <- featureOrderedExtracted\$cluster
    rowmeta_clusterTopK <- rowmeta_cluster[seq_len(topK)]
    
    heatmap2 <- Heatmap(
      rowmeta_clusterTopK,
      name = "cluster"
    )
    
    # Save combined heatmap to PDF
    pdf("de_heatmap.pdf", width = 10, height = 8)
    draw(heatmap2 + heatmap1)
    dev.off()

    writeLines(c(
        '"BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS":',
        paste0('    cytoKernel: ', as.character(packageVersion('cytoKernel')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_analysis.csv versions.yml
    """
}

workflow BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, group_labels.csv ] ]

    main:
    BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_CYTOKERNEL_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.versions
}
