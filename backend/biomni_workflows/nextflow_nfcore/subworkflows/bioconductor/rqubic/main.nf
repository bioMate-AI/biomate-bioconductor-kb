#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rqubic — qualitative_biclustering_pipeline
// Perform qualitative biclustering on gene expression data from an ExpressionSet object.
// Input: BicatYeast, demo.exprs
// Container: quay.io/biocontainers/bioconductor-rqubic:1.56.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, biclust, rqubic
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load required libraries and prepare the ExpressionSet with sample metadata
//  * 2. [Core Analysis] Discretize the expression data using quantile discretization
//  * 3. [Core Analysis] Generate seeds from the discretized matrix
//  * 4. [Core Analysis] Identify biclusters using the heuristic QUBIC algorithm
//  * 5. [Visualization & Output] Visualize the identified biclusters using parallel coordinates plots

nextflow.enable.dsl = 2

process BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE {
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
    library(rqubic)
    library(Biobase)
    library(biclust)
    
    # 1. Load required libraries and prepare the ExpressionSet with sample metadata
    # Read BicatYeast from the working directory
    if (file.exists("BicatYeast.rds")) {
      BicatYeast <- readRDS("BicatYeast.rds")
    } else if (file.exists("BicatYeast.csv")) {
      BicatYeast <- as.matrix(read.csv("BicatYeast.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("BicatYeast")) {
      BicatYeast <- readRDS("BicatYeast")
    } else {
      stop("Error: 'BicatYeast' file not found in the working directory.")
    }
    
    # Read demo.exprs from the working directory
    if (file.exists("demo.exprs.rds")) {
      demo.exprs <- readRDS("demo.exprs.rds")
    } else if (file.exists("demo.exprs.csv")) {
      exprs_mat <- as.matrix(read.csv("demo.exprs.csv", row.names = 1, check.names = FALSE))
      demo.exprs <- new("ExpressionSet", exprs = exprs_mat)
    } else if (file.exists("demo.exprs")) {
      demo.exprs <- readRDS("demo.exprs")
    } else {
      # Fallback: construct from BicatYeast if not explicitly provided as a separate file
      demo.exprs <- new("ExpressionSet", exprs = BicatYeast)
    }
    
    # Process condition information and assign metadata if not already present
    if (ncol(pData(demo.exprs)) == 0) {
      pData(demo.exprs) <- data.frame(sample = colnames(demo.exprs), row.names = colnames(demo.exprs))
    }
    
    # 2. Discretize the expression data using quantile discretization
    demo.disc <- quantileDiscretize(demo.exprs)
    
    # 3. Generate seeds from the discretized matrix
    demo.seed <- generateSeeds(demo.disc)
    
    # 4. Identify biclusters using the heuristic QUBIC algorithm
    demo.bic <- quBicluster(demo.seed, demo.disc)
    
    # Save results to files
    saveRDS(demo.disc, "demo_disc.rds")
    saveRDS(demo.seed, "demo_seed.rds")
    saveRDS(demo.bic, "demo_bic.rds")
    
    # Write summary of the biclusters
    sink("bicluster_summary.txt")
    print(demo.bic)
    sink()
    
    # 5. Visualize the identified biclusters using parallel coordinates plots
    pdf("bicluster_parallel_coordinates.pdf", width = 10, height = 7)
    if (demo.bic@Number > 0) {
      parallelCoordinates(BicatYeast, demo.bic, number=min(3, demo.bic@Number), plotBoth=FALSE, 
                          compare=TRUE, col="#004495", pch=1)
    }
    dev.off()

    writeLines(c(
        '"BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE":',
        paste0('    rqubic: ', as.character(packageVersion('rqubic')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qualitative_biclustering_pipeline.csv versions.yml
    """
}

workflow BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BicatYeast, demo.exprs ] ]

    main:
    BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE.out.tables
    plots    = BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE.out.plots
    objects  = BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE.out.objects
    versions = BIOC_RQUBIC_QUALITATIVE_BICLUSTERING_PIPELINE.out.versions
}
