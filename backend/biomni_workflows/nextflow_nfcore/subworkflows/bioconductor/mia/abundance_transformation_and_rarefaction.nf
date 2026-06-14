#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mia — abundance_transformation_and_rarefaction
// Transform raw microbiome count data and perform rarefaction (subsampling to equal depth) for downstream statistical analyses.
// Input: enterotype.RDS, GlobalPatterns.RDS
// Container: quay.io/biocontainers/bioconductor-mia:1.18.0--r45ha27e39d_0
// R packages: MultiAssayExperiment, mia
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, mia
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Load user input files
//  * 2. [Core Analysis] Apply mathematical transformations (log10 with a
//  * 3. [Core Analysis] Subsample the raw counts to an equal number of counts per
//  * 4. [Core Analysis] Combine original and subsampled datasets into a
//  * 5. [Core Analysis] Save outputs

nextflow.enable.dsl = 2

process BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("MultiAssayExperiment", "mia", "SummarizedExperiment")
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
    
    # Load required lib    library(SummarizedExperiment)
raries
    library(mia)
    library(MultiAssayExperiment)
    
    # --- Load user input files ---
    if (!file.exists("enterotype.RDS") || !file.exists("GlobalPatterns.RDS")) {
        stop("Required input files 'enterotype.RDS' and/or 'GlobalPatterns.RDS' not found in the working directory.")
    }
    
    enterotype <- readRDS("enterotype.RDS")
    GlobalPatterns <- readRDS("GlobalPatterns.RDS")
    
    # --- Apply mathematical transformations (log10 with a ---
    anterotype <- transformAssay(enterotype, method = "log10", pseudocount = 1)
    
    # --- Subsample the raw counts to an equal number of counts per ---
    tse.subsampled <- rarefyAssay(
        GlobalPatterns, 
        sample = 60000, 
        name = "subsampled",
        replace = TRUE,
        seed = 1938)
    
    # --- Combine original and subsampled datasets into a ---
    mae <- MultiAssayExperiment(
        c("originalTreeSE" = GlobalPatterns,
        "subsampledTreeSE" = tse.subsampled))
    
    # Extract the subsampled TreeSE from the MAE
    subsampled_extracted <- experiments(mae)\$subsampledTreeSE
    
    # --- Save outputs ---
    saveRDS(anterotype, "anterotype.rds")
    saveRDS(tse.subsampled, "tse_subsampled.rds")
    saveRDS(mae, "mae.rds")
    
    # Export subset of transformed assay to CSV for downstream inspection
    transformed_matrix <- as.matrix(assay(anterotype, "log10"))
    write.csv(head(transformed_matrix, 100), "anterotype_log10_top100.csv")
    
    # Export subset of subsampled assay to CSV for downstream inspection
    subsampled_matrix <- as.matrix(assay(subsampled_extracted, "subsampled"))
    write.csv(head(subsampled_matrix, 100), "tse_subsampled_top100.csv")
    
    cat("Pipeline completed successfully. Outputs saved to 'anterotype.rds', 'tse_subsampled.rds', 'mae.rds', and summary CSVs.\n")

    writeLines(c(
        '"BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION":',
        paste0('    mia: ', as.character(packageVersion('mia')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_abundance_transformation_and_rarefaction.csv versions.yml
    """
}

workflow BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ enterotype.RDS, GlobalPatterns.RDS ] ]

    main:
    BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION(ch_input)

    emit:
    tables   = BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION.out.tables
    plots    = BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION.out.plots
    objects  = BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION.out.objects
    versions = BIOC_MIA_ABUNDANCE_TRANSFORMATION_AND_RAREFACTION.out.versions
}
