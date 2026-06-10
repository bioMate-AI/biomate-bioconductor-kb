#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: destiny — projection_prediction
// Project new cell samples into an existing diffusion map.
// Input: guo
// Container: quay.io/biocontainers/bioconductor-destiny:3.24.0--r45ha27e39d_0
// Requires: Biobase, destiny
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Subset reference cells and create reference DiffusionMap
//  * 2. [Core Analysis] Subset new cells
//  * 3. [Core Analysis] Predict new coordinates using dm_predict
//  * 4. [Visualization & Output] Plot reference map with projected new cells

nextflow.enable.dsl = 2

process BIOC_DESTINY_PROJECTION_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biobase", "destiny")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(destiny)
    library(Biobase)
    
    # Read the input ExpressionSet 'guo' from the working directory
    if (file.exists("guo")) {
      guo <- readRDS("guo")
    } else if (file.exists("guo.rds")) {
      guo <- readRDS("guo.rds")
    } else {
      stop("Error: Input file 'guo' or 'guo.rds' not found in the working directory.")
    }
    
    # 1. Subset reference cells and create reference DiffusionMap
    ct64 <- guo[, guo \$ num_cells == 64 ]
    dm64 <- DiffusionMap (ct64)
    
    # 2. Subset new cells
    ct32 <- guo[, guo \$ num_cells == 32 ]
    
    # 3. Predict new coordinates using dm_predict
    pred32 <- dm_predict (dm64, ct32)
    
    # 4. Plot reference map with projected new cells and save to PDF
    pdf("projection_plot.pdf", width = 8, height = 8)
    plot (dm64, 1 : 2 , col = palette ()[[ 6 ]], new_dcs = pred32, col_new = palette ()[[ 4 ]])
    dev.off()
    
    # Save meaningful results to the working directory
    saveRDS(dm64, "reference_diffusion_map_64.rds")
    saveRDS(pred32, "predicted_coordinates_32.rds")
    write.csv(as.data.frame(pred32), "predicted_coordinates_32.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_DESTINY_PROJECTION_PREDICTION":',
        paste0('    destiny: ', as.character(packageVersion('destiny')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_projection_prediction.csv versions.yml
    """
}

workflow BIOC_DESTINY_PROJECTION_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ guo ] ]

    main:
    BIOC_DESTINY_PROJECTION_PREDICTION(ch_input)

    emit:
    tables   = BIOC_DESTINY_PROJECTION_PREDICTION.out.tables
    plots    = BIOC_DESTINY_PROJECTION_PREDICTION.out.plots
    objects  = BIOC_DESTINY_PROJECTION_PREDICTION.out.objects
    versions = BIOC_DESTINY_PROJECTION_PREDICTION.out.versions
}
