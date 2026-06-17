#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: simPIC — scatac_simulation_and_comparison
// Estimate parameters from a real scATAC-seq count matrix, simulate synthetic datasets with custom parameters (including multiple cell types and batch effects), a
// Input: test.rds
// Container: quay.io/biocontainers/bioconductor-simpic:1.6.0--r45hdfd78af_0
// R packages: SingleCellExperiment, ggplot2, scater, simPIC
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, ggplot2, scater, simPIC
// Visualizations: PCA plot
// QC: cell QC metrics, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the real count matrix
//  * 2. [Core Analysis] Estimate parameters using simPICestimate
//  * 3. [Core Analysis] Simulate synthetic counts using simPICsimulate
//  * 4. [Core Analysis] Customize simulation parameters using setsimPICparameters and simPICgetparameters
//  * 5. [Core Analysis] Simulate multiple cell types (groups) and batch effects
//  * 6. [Core Analysis] Compare simulated datasets using simPICcompare

nextflow.enable.dsl = 2

process BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("SingleCellExperiment", "ggplot2", "scater", "simPIC", "SummarizedExperiment")
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
    
    # Load required packages
    suppressPackageStartupMessages({
        library(SummarizedExperiment)
        library(simPIC)
        library(scater)
        library(ggplot2)
    })
    
    # Set seed for reproducibility
    set.seed(567)
    
    # 1. Load the real count matrix
    if (!file.exists("test.rds")) {
        stop("Required input file 'test.rds' not found in the working directory.")
    }
    counts <- readRDS("test.rds")
    
    # Check that counts is a dgCMatrix and inspect dimensions
    class(counts)
    typeof(counts)
    dim(counts)
    counts[1:5, 1:5]
    
    # 2. Estimate parameters using simPICestimate
    est <- simPICestimate(counts)
    
    # 3. Simulate synthetic counts using simPICsimulate
    sim <- simPICsimulate(est)
    
    # 4. Customize simulation parameters using setsimPICparameters and simPICgetparameters
    sim.params <- newsimPICcount()
    sim.params
    
    simPICget(sim.params, "nPeaks")
    sim.params <- setsimPICparameters(sim.params, nPeaks = 2000)
    simPICget(sim.params, "nPeaks")
    
    sim.params <- setsimPICparameters(sim.params,
        update = list(nPeaks = 8000, nCells = 500)
    )
    
    params <- simPICgetparameters(
        sim.params,
        c("nPeaks", "nCells", "peak.mean.shape")
    )
    
    params <- setsimPICparameters(sim.params,
        lib.size.sdlog = 3.5, lib.size.meanlog = 9.07
    )
    params
    
    new <- newsimPICcount()
    new <- simPICestimate(counts)
    
    sim <- simPICsimulate(new, nCells = 500)
    sim
    
    # Access simulated counts and metadata
    counts(sim)[1:5, 1:5]
    head(rowData(sim))
    head(colData(sim))
    names(assays(sim))
    
    # Save simulated SCE object and metadata
    saveRDS(sim, "sim_sce.rds")
    write.csv(as.data.frame(rowData(sim)), "sim_rowData.csv", row.names = TRUE)
    write.csv(as.data.frame(colData(sim)), "sim_colData.csv", row.names = TRUE)
    
    # 5. Compare simulated datasets using simPICcompare
    sim1 <- simPICsimulate(nPeaks = 2000, nCells = 500)
    sim2 <- simPICsimulate(nPeaks = 2000, nCells = 500)
    comparison <- simPICcompare(list(real = sim1, simPIC = sim2))
    
    names(comparison)
    names(comparison\$Plots)
    
    # Save comparison plot
    pdf("comparison_means.pdf", width = 7, height = 5)
    print(comparison\$Plots\$Means)
    dev.off()
    
    # 6. Simulate multiple cell types (groups) and batch effects
    # Equal proportions
    sim <- simPICsimulate(new, method = "groups", 
                    nGroups = 2, group.prob = c(0.5, 0.5))
    
    sim <- logNormCounts(sim)
    sim <- scater::runPCA(sim)
    
    pdf("pca_sim_equal_proportions.pdf", width = 7, height = 5)
    print(plotPCASCE(sim, color_by="Group"))
    dev.off()
    
    # Variable proportions
    sim_multi <- simPICsimulate(new, method ="groups", 
                                nGroups = 2, 
                                group.prob = c(0.7, 0.3))
    
    sim_multi <- logNormCounts(sim_multi)
    sim_multi <- runPCA(sim_multi)
    
    pdf("pca_sim_variable_proportions.pdf", width = 7, height = 5)
    print(plotPCASCE(sim_multi, color_by="Group"))
    dev.off()
    
    # Batch effects
    set.seed(567)
    sim_batch <- simPICsimulate(new, method="groups",
                                nGroups=2, nBatches=2,
                                group.prob=c(0.5, 0.5),
                                batchCells=c(250,250))
    
    sim_batch <- logNormCounts(sim_batch)
    sim_batch <- runPCA(sim_batch)
    
    pdf("pca_sim_batch_effects.pdf", width = 7, height = 5)
    print(plotPCASCE(sim_batch, color_by="Batch", shape_by="Group"))
    dev.off()
    
    # Save simulated objects for downstream analysis
    saveRDS(sim, "sim_equal_proportions.rds")
    saveRDS(sim_multi, "sim_variable_proportions.rds")
    saveRDS(sim_batch, "sim_batch_effects.rds")
    
    # Print citation and session info
    citation("simPIC")
    sessionInfo()

    writeLines(c(
        '"BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON":',
        paste0('    simPIC: ', as.character(packageVersion('simPIC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scatac_simulation_and_comparison.csv versions.yml
    """
}

workflow BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.rds ] ]

    main:
    BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON(ch_input)

    emit:
    tables   = BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON.out.tables
    plots    = BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON.out.plots
    objects  = BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON.out.objects
    versions = BIOC_SIMPIC_SCATAC_SIMULATION_AND_COMPARISON.out.versions
}
