#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spoon — custom_weighted_svg_workflow
// Generate weights and rescale logcounts to use with alternative spatially variable gene detection tools that do not natively support weights.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-spoon:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Matrix, SpatialExperiment, SummarizedExperiment, spoon
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate observation weights using generate_weights()
//  * 2. [Core Analysis] Rescale the logcounts matrix by multiplying with the transposed weights
//  * 3. [Core Analysis] Store the rescaled matrix as a new assay "weighted_logcounts" in the SpatialExperiment object

nextflow.enable.dsl = 2

process BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW {
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
        
        # Load required libraries
        library(SpatialExperiment)
        library(spoon)
        library(BiocParallel)
        library(Matrix)
        
        # 1. Read the input SpatialExperiment object from the working directory
        if (!file.exists("spe.rds")) {
          stop("Input file 'spe.rds' not found in the working directory.")
        }
        spe <- readRDS("spe.rds")
        
        # Ensure the logcounts assay exists
        if (!"logcounts" %in% assayNames(spe)) {
          stop("The input SpatialExperiment object must contain a 'logcounts' assay.")
        }
        
        # 2. Generate observation weights using generate_weights()
        # Keeping the exact documented function call and arguments
        weights <- generate_weights(input = spe,
                                    stabilize = TRUE,
                                    BPPARAM = MulticoreParam(workers = 1,
                                                             RNGseed = 4))
        
        # 3. Rescale the logcounts matrix by multiplying with the transposed weights
        # and store the rescaled matrix as a new assay "weighted_logcounts"
        assay_name <- "logcounts"
        weighted_logcounts <- t(weights)*assays(spe)[[assay_name]]
        assay(spe, "weighted_logcounts") <- weighted_logcounts
        
        # 4. Save the meaningful results to the working directory
        # Save the updated SpatialExperiment object
        saveRDS(spe, "spe_weighted.rds")
        
        # Save the generated weights matrix
        saveRDS(weights, "weights.rds")
        
        # Save a summary or subset of the weighted logcounts as a CSV table
        weighted_matrix_subset <- as.matrix(weighted_logcounts[1:min(100, nrow(weighted_logcounts)), 1:min(100, ncol(weighted_logcounts))])
        write.csv(weighted_matrix_subset, "weighted_logcounts_subset.csv", row.names = TRUE)
        
        # Save basic summary statistics of the weights
        weights_sum <- summary(as.vector(weights))
        weights_summary <- data.frame(
          Statistic = names(weights_sum),
          Value = as.vector(weights_sum)
        )
        write.csv(weights_summary, "weights_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW":',
        paste0('    spoon: ', as.character(packageVersion('spoon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_weighted_svg_workflow.csv versions.yml
    """
}

workflow BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW.out.tables
    plots    = BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW.out.plots
    objects  = BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW.out.objects
    versions = BIOC_SPOON_CUSTOM_WEIGHTED_SVG_WORKFLOW.out.versions
}
