#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spoon — weighted_nnsvg_workflow
// Identify spatially variable genes in spatial transcriptomics data using weighted nearest-neighbor Gaussian process regression to control for the mean-variance r
// Input: spe
// Container: quay.io/biocontainers/bioconductor-spoon:1.6.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, Matrix, SpatialExperiment, nnSVG, scuttle, spoon
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter out low-quality genes and spots with zero counts
//  * 2. [Core Analysis] Compute library size factors and log-normalize counts
//  * 3. [Core Analysis] Generate observation weights using generate_weights()
//  * 4. [Core Analysis] Run weighted SVG detection using weighted_nnSVG()
//  * 5. [Core Analysis] Retrieve results from the rowData of the SpatialExperiment object

nextflow.enable.dsl = 2

process BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW {
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
    .bm_deps <- c("nnSVG", "SpatialExperiment", "BRISC", "BiocParallel", "scuttle", "Matrix", "spoon")
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
    library(nnSVG)
    library(SpatialExperiment)
    library(BRISC)
    library(BiocParallel)
    library(scuttle)
    library(Matrix)
    library(spoon)
    
    # 1. Load the input SpatialExperiment object from the working directory
    if (!file.exists("spe")) {
      stop("Input file 'spe' not found in the working directory.")
    }
    spe <- readRDS("spe")
    
    # 2. Preprocessing
    # Keep spots over tissue
    if ("in_tissue" %in% colnames(colData(spe))) {
      spe <- spe[, colData(spe)\$in_tissue == 1]
    }
    
    # Filter out low quality genes
    spe <- filter_genes(spe)
    
    # Calculate logcounts (log-transformed normalized counts)
    spe <- computeLibraryFactors(spe)
    spe <- logNormCounts(spe)
    
    # Remove spots with zero counts
    spe <- spe[, colSums(logcounts(spe)) > 0]
    
    # 3. Generate observation weights
    weights <- generate_weights(input = spe,
                                stabilize = TRUE,
                                BPPARAM = MulticoreParam(workers = 1,
                                                         RNGseed = 4))
    
    # Save the generated weights
    saveRDS(weights, "weights.rds")
    
    # 4. Run weighted SVG detection
    spe <- weighted_nnSVG(input = spe,
                          w = weights,
                          BPPARAM = MulticoreParam(workers = 1, RNGseed = 5))
    
    # 5. Retrieve and save results
    results_df <- as.data.frame(rowData(spe))
    write.csv(results_df, "weighted_svg_results.csv", row.names = TRUE)
    
    # Save the final SpatialExperiment object
    saveRDS(spe, "spe_weighted_nnsvg.rds")

    writeLines(c(
        '"BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW":',
        paste0('    spoon: ', as.character(packageVersion('spoon')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weighted_nnsvg_workflow.csv versions.yml
    """
}

workflow BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ spe ] ]

    main:
    BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW.out.tables
    plots    = BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW.out.plots
    objects  = BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW.out.objects
    versions = BIOC_SPOON_WEIGHTED_NNSVG_WORKFLOW.out.versions
}
