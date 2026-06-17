#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spatialDE — spatial_experiment_workflow
// Identify, classify, and cluster spatially variable genes directly using a SpatialExperiment object.
// Input: spe
// Container: quay.io/biocontainers/bioconductor-spatialde:1.16.0--r45hdfd78af_0
// R packages: SpatialExperiment, spatialDE
// Bioconductor: 3.20 | R: 4.4
// Requires: SpatialExperiment, spatialDE
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run SpatialDE on the SpatialExperiment object using spatialDE()
//  * 2. [Visualization & Output] Visualize spatial patterns of multiple genes using multiGenePlots()
//  * 3. [Core Analysis] Classify SVGs into interpretable classes using modelSearch()
//  * 4. [Core Analysis] Group SVGs into spatial patterns using spatialPatterns()

nextflow.enable.dsl = 2

process BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW {
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
    .bm_deps <- c("SpatialExperiment", "spatialDE")
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
        library(spatialDE)
        library(SpatialExperiment)
        
        # Read the user input SpatialExperiment object from the working directory
        if (file.exists("spe")) {
            spe <- readRDS("spe")
        } else if (file.exists("spe.rds")) {
            spe <- readRDS("spe.rds")
        } else {
            stop("Error: Input file 'spe' or 'spe.rds' not found in the working directory.")
        }
        
        # 1. Run SpatialDE on the SpatialExperiment object
        out <- spatialDE(spe, assay_type = "counts", verbose = FALSE)
        spe_results <- out[out\$qval < 0.05, ]
        ordered_spe_results <- spe_results[order(spe_results\$qval), ]
        
        # 2. Visualize spatial patterns of multiple genes
        tryCatch({
            pdf("multi_gene_plots.pdf", width = 10, height = 10)
            print(multiGenePlots(spe,
                assay_type = "counts",
                na.omit(head(ordered_spe_results\$g, 6)),
                point_size = 4,
                viridis_option = "D",
                dark_theme = FALSE
            ))
            dev.off()
        }, error = function(e) {
            message("multiGenePlots failed or was skipped: ", e\$message)
            if (dev.cur() > 1) dev.off()
        })
        
        # 3. Classify SVGs into interpretable classes
        msearch <- modelSearch(spe,
            de_results = out, qval_thresh = 0.05,
            verbose = FALSE
        )
        
        # 4. Group SVGs into spatial patterns
        de_results <- out
        spatterns <- spatialPatterns(spe,
            de_results = de_results, qval_thresh = 0.05,
            n_patterns = 4L, length = 1.5, verbose = FALSE
        )
        
        # Write named output files for the meaningful results
        write.csv(out, "spatialDE_results.csv", row.names = FALSE)
        write.csv(ordered_spe_results, "ordered_spe_results.csv", row.names = FALSE)
        write.csv(msearch, "model_search_results.csv", row.names = FALSE)
        
        if (!is.null(spatterns) && !is.null(spatterns\$pattern_results)) {
            write.csv(spatterns\$pattern_results, "spatial_patterns_results.csv", row.names = FALSE)
        }
        saveRDS(spatterns, "spatial_patterns.rds")

    writeLines(c(
        '"BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW":',
        paste0('    spatialDE: ', as.character(packageVersion('spatialDE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spatial_experiment_workflow.csv versions.yml
    """
}

workflow BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW.out.tables
    plots    = BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW.out.plots
    objects  = BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW.out.objects
    versions = BIOC_SPATIALDE_SPATIAL_EXPERIMENT_WORKFLOW.out.versions
}
