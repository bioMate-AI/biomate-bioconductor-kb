#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MOMA — moma_multi_omic_pipeline
// Infer candidate master regulator proteins and genomic driver connections from multi-omics data and pathway networks.
// Input: example.gbm.mae, gbm.pathways
// Container: quay.io/biocontainers/bioconductor-moma:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MOMA, MultiAssayExperiment, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the MOMA object using MomaConstructor
//  * 2. [Core Analysis] Run the DIGGIT inference algorithm using runDIGGIT
//  * 3. [Core Analysis] Infer robust computational predictions using makeInteractions
//  * 4. [Core Analysis] Rank candidate Master Regulators using Rank
//  * 5. [Core Analysis] Cluster samples based on protein ranks using Cluster and assign the optimal cluster solution
//  * 6. [Core Analysis] Perform genomic saturation analysis using saturationCalculation
//  * 7. [Visualization & Output] Generate saturation and oncoprint plots using makeSaturationPlots
//  * 8. [Visualization & Output] Save results using saveData

nextflow.enable.dsl = 2

process BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("MOMA", "ggplot2", "MultiAssayExperiment")
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
    library(MOMA)
    library(ggplot2)
    library(grid)
    library(MultiAssayExperiment)
    
    # 1. Read User Input Files from the working directory
    # The files are expected to be saved as RDS files containing the respective objects.
    example.gbm.mae <- readRDS("example.gbm.mae")
    gbm.pathways <- readRDS("gbm.pathways")
    
    # Create output directory if it doesn't exist
    dir.create("outputs", showWarnings = FALSE, recursive = TRUE)
    
    # 2. Initialize the MOMA object
    momaObj <- MomaConstructor(example.gbm.mae, gbm.pathways)
    
    # 3. Run DIGGIT inference algorithm
    momaObj\$runDIGGIT()
    
    # 4. Infer robust computational predictions
    momaObj\$makeInteractions()
    
    # 5. Rank candidate Master Regulators
    momaObj\$Rank()
    
    # 6. Cluster samples and assign the optimal cluster solution
    momaObj\$Cluster()
    
    # 7. Perform genomic saturation analysis
    momaObj\$saturationCalculation()
    
    # Extract and print checkpoint for cluster 1
    cluster1.checkpoint <- momaObj\$checkpoints[[1]]
    print(cluster1.checkpoint[1:5])
    
    # Save checkpoint to a text file
    writeLines(as.character(cluster1.checkpoint), con = "outputs/cluster1_checkpoint.txt")
    
    # 8. Generate saturation and oncoprint plots
    plots <- makeSaturationPlots(momaObj)
    
    # Save plots to a PDF file
    pdf("outputs/moma_saturation_plots.pdf", width = 10, height = 8)
    
    # Draw the oncoprint plot (grid-based)
    grid.newpage()
    grid.draw(plots\$oncoprint.plots[[1]])
    
    # Draw the saturation curve plot (ggplot-based)
    grid.newpage()
    p <- plots\$curve.plots[[1]] +
      ggtitle("Genomic Saturation Curve for Cluster 1")
    print(p)
    
    dev.off()
    
    # 9. Save results using the MOMA saveData method
    momaObj\$saveData(output.folder = "outputs", "hypotheses", "checkpoints")
    
    # Save the complete MOMA object for downstream analysis
    saveRDS(momaObj, file = "outputs/momaObj_completed.rds")

    writeLines(c(
        '"BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE":',
        paste0('    MOMA: ', as.character(packageVersion('MOMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_moma_multi_omic_pipeline.csv versions.yml
    """
}

workflow BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.gbm.mae, gbm.pathways ] ]

    main:
    BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE.out.tables
    plots    = BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE.out.plots
    objects  = BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE.out.objects
    versions = BIOC_MOMA_MOMA_MULTI_OMIC_PIPELINE.out.versions
}
