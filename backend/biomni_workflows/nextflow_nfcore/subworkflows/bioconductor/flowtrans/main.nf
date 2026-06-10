#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowTrans — flow_cytometry_transformation_optimization
// Optimize transformation parameters for flow cytometry channels to achieve multivariate normality and transform the data.
// Input: flowFrame.rds
// Container: quay.io/biocontainers/bioconductor-flowtrans:1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowTrans, flowViz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the flow cytometry data
//  * 2. [Core Analysis] Run flowTrans to optimize parameters and transform the selected dimensions
//  * 3. [Core Analysis] Extract the optimized parameters for downstream use
//  * 4. [Visualization & Output] Plot the untransformed and transformed data to visually inspect the results
//  * 5. [Core Analysis] Run flowTrans with parameters.only=TRUE to obtain parameters for integration into flowCore workflows

nextflow.enable.dsl = 2

process BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    
    # Load required libraries
    library(flowCore)
    library(flowTrans)
    library(flowViz)
    
    # 1. Load the flow cytometry data
    # Read the user input flowFrame
    ff <- readRDS("flowFrame.rds")
    
    # Dynamically select the first two existing column names for the dims argument
    dims <- colnames(ff)[1:2]
    
    # Partition the flowFrame into 4 subsets to mimic the list of flowFrames in the vignette
    ff_list <- list(ff, ff, ff, ff)
    
    # 2. Run flowTrans to optimize parameters and transform the selected dimensions
    transformed <- lapply(ff_list, function(x) {
      flowTrans(dat=x, fun="mclMultivArcSinh", dims=dims, n2f=FALSE, parameters.only=FALSE)
    })
    
    # 3. Extract the optimized parameters for downstream use
    parameters <- do.call(rbind, lapply(transformed, function(x) extractParams(x)[[1]]))
    
    # Save parameters to CSV
    write.csv(parameters, "transformed_parameters.csv", row.names = TRUE)
    
    # Save the transformed list of flowFrames
    saveRDS(transformed, "transformed_flowframes.rds")
    
    # 4. Plot the untransformed and transformed data to visually inspect the results
    pdf("transformation_plots.pdf", width = 10, height = 10)
    par(mfrow = c(2, 2))
    plot(ff_list[[2]], dims, main = "Untransformed sample")
    contour(ff_list[[2]], dims, add=TRUE)
    plot(transformed[[2]]\$result, dims, main = "Transformed sample")
    contour(transformed[[2]]\$result, dims, add=TRUE)
    plot(ff_list[[4]], dims, main = "Untransformed sample")
    contour(ff_list[[4]], dims, add=TRUE)
    plot(transformed[[4]]\$result, dims, main = "Transformed sample")
    contour(transformed[[4]]\$result, dims, add=TRUE)
    dev.off()
    
    # 5. Run flowTrans with parameters.only=TRUE to obtain parameters for integration into flowCore workflows
    transformed2 <- flowTrans(dat=ff_list[[2]], fun="mclMultivArcSinh", dims=dims, n2f=FALSE, parameters.only=TRUE)
    
    # Save the parameters.only result
    saveRDS(transformed2, "transformed2_parameters.rds")

    writeLines(c(
        '"BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION":',
        paste0('    flowTrans: ', as.character(packageVersion('flowTrans')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flow_cytometry_transformation_optimization.csv versions.yml
    """
}

workflow BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ flowFrame.rds ] ]

    main:
    BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION(ch_input)

    emit:
    tables   = BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION.out.tables
    plots    = BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION.out.plots
    objects  = BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION.out.objects
    versions = BIOC_FLOWTRANS_FLOW_CYTOMETRY_TRANSFORMATION_OPTIMIZATION.out.versions
}
