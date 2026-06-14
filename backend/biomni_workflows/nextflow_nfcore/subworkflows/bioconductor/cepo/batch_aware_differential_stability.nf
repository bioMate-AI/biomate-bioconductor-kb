#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cepo — batch_aware_differential_stability
// Perform differential stability analysis across multiple batches using the block argument to avoid batch effects.
// Input: sce_pancreas
// Container: quay.io/biocontainers/bioconductor-cepo:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Cepo, SingleCellExperiment, scater
// Visualizations: density plot
// QC: cell QC metrics, count normalization, normalization diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and normalize
//  * 2. [Core Analysis] Run Cepo with the block argument to perform analysis independently per batch
//  * 3. [Core Analysis] Extract top genes from the averaged results

nextflow.enable.dsl = 2

process BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY {
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
    .bm_deps <- c("Cepo", "scater")
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
    
    library(Cepo)
    library(scater)
    
    # 1. Load data and normalize
    if (file.exists("sce_pancreas")) {
      sce_pancreas <- readRDS("sce_pancreas")
    } else if (file.exists("sce_pancreas.rds")) {
      sce_pancreas <- readRDS("sce_pancreas.rds")
    } else {
      stop("Required input file 'sce_pancreas' or 'sce_pancreas.rds' not found in the working directory.")
    }
    
    sce = sce_pancreas
    sce = scater::logNormCounts(sce)
    
    # 2. Run Cepo with the block argument to perform analysis independently per batch
    ds_res_batches = Cepo::Cepo(exprsMat = logcounts(sce),
                                cellTypes = sce\$cellTypes,
                                block = sce\$batch,
                                minCelltype = 2)
    names(ds_res_batches)
    
    # 3. Extract top genes from the averaged results
    cepo_genes = Cepo::topGenes(ds_res_batches\$average, n = 3)
    
    # 4. Save outputs to the working directory
    # Save the complete Cepo results list
    saveRDS(ds_res_batches, "ds_res_batches.rds")
    
    # Save the top genes as a CSV file
    cepo_genes_df <- as.data.frame(cepo_genes)
    write.csv(cepo_genes_df, "top_cepo_genes.csv", row.names = FALSE)
    
    # Save the average differential stability statistics
    if (!is.null(ds_res_batches\$average\$stats)) {
      write.csv(as.data.frame(ds_res_batches\$average\$stats), "cepo_average_stats.csv")
    }
    
    # Generate and save density plots for the top differentially stable genes
    tryCatch({
      pdf("cepo_densities.pdf", width = 10, height = 8)
      Cepo::plotDensities(x = sce,
                          cepoOutput = ds_res_batches\$average,
                          nGenes = 2,
                          assay = "logcounts",
                          celltypeColumn = "cellTypes")
      dev.off()
    }, error = function(e) {
      warning("Could not generate density plots: ", e\$message)
      if (dev.cur() > 1) dev.off()
    })

    writeLines(c(
        '"BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY":',
        paste0('    Cepo: ', as.character(packageVersion('Cepo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_batch_aware_differential_stability.csv versions.yml
    """
}

workflow BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce_pancreas ] ]

    main:
    BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY(ch_input)

    emit:
    tables   = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.tables
    plots    = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.plots
    objects  = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.objects
    versions = BIOC_CEPO_BATCH_AWARE_DIFFERENTIAL_STABILITY.out.versions
}
