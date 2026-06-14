#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDD — single_cell_simulation
// Simulate a single-cell RNA-seq dataset with specified numbers of differentially distributed and equivalently distributed genes based on real pilot data.
// Input: pilot_data.rds
// Container: quay.io/biocontainers/bioconductor-scdd:1.34.0--r45hdfd78af_0
// R packages: SingleCellExperiment, scDD
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scDD
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the pilot SingleCellExperiment dataset
//  * 2. [Core Analysis] Set simulation parameters including the number of genes for each pattern (DE, DP, DM, DB, EE, EP), sample size, and random seed
//  * 3. [Core Analysis] Run simulateSet to generate the simulated dataset
//  * 4. [Core Analysis] Extract the simulated expression values and true category/fold-change metadata

nextflow.enable.dsl = 2

process BIOC_SCDD_SINGLE_CELL_SIMULATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SingleCellExperiment", "scDD", "SummarizedExperiment")
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
    library(scDD)
    library(SummarizedExperiment)
    
    # 1. Load the pilot SingleCellExperiment dataset
    # The pipeline reads pilot_data.rds from the working directory
    scDatEx <- readRDS("pilot_data.rds")
    
    # 2. Set simulation parameters including the number of genes for each pattern, sample size, and random seed
    nDE <- 5
    nDP <- 5
    nDM <- 5
    nDB <- 5
    nEE <- 5
    nEP <- 5
    numSamples <- 100
    seed <- 816
    
    # 3. Run simulateSet to generate the simulated dataset
    SD <- simulateSet(scDatEx, 
                      numSamples=numSamples, 
                      nDE=nDE, 
                      nDP=nDP, 
                      nDM=nDM, 
                      nDB=nDB, 
                      nEE=nEE, 
                      nEP=nEP, 
                      sd.range=c(2,2), 
                      modeFC=4, 
                      plots=FALSE, 
                      random.seed=seed)
    
    # 4. Extract the simulated expression values and true category/fold-change metadata
    sim_metadata <- as.data.frame(rowData(SD))
    head(sim_metadata)
    
    # Write named output files for the meaningful results
    saveRDS(SD, "simulated_dataset.rds")
    write.csv(sim_metadata, "simulated_gene_metadata.csv", row.names=TRUE)
    
    # Extract and save simulated expression values (normcounts)
    sim_exprs <- as.matrix(normcounts(SD))
    write.csv(sim_exprs, "simulated_expression_counts.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_SCDD_SINGLE_CELL_SIMULATION":',
        paste0('    scDD: ', as.character(packageVersion('scDD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_simulation.csv versions.yml
    """
}

workflow BIOC_SCDD_SINGLE_CELL_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pilot_data.rds ] ]

    main:
    BIOC_SCDD_SINGLE_CELL_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SCDD_SINGLE_CELL_SIMULATION.out.tables
    plots    = BIOC_SCDD_SINGLE_CELL_SIMULATION.out.plots
    objects  = BIOC_SCDD_SINGLE_CELL_SIMULATION.out.objects
    versions = BIOC_SCDD_SINGLE_CELL_SIMULATION.out.versions
}
