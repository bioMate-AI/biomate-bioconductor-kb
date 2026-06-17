#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miloR — da_glmm_random_effects
// Perform differential abundance testing using a Generalized Linear Mixed Model (GLMM) to account for random effects and dependencies between observations.
// Input: pbmc.sce, pbmc.design
// Container: quay.io/biocontainers/bioconductor-milor:2.6.0--r45ha27e39d_0
// R packages: BiocParallel, SingleCellExperiment, dplyr, ggplot2, miloR, patchwork, scater, scran
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, SingleCellExperiment, dplyr, ggplot2, miloR, patchwork, scater, scran
// Visualizations: UMAP plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create Milo object
//  * 2. [Input & Preparation] Build KNN graph
//  * 3. [Input & Preparation] Define representative neighbourhoods
//  * 4. [Core Analysis] Count cells in neighbourhoods
//  * 5. [Core Analysis] Check for perfect separation
//  * 6. [Core Analysis] Test for differential abundance using GLMM

nextflow.enable.dsl = 2

process BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("BiocParallel", "SingleCellExperiment", "dplyr", "ggplot2", "miloR", "patchwork", "scater", "scran", "SummarizedExperiment")
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
        library(miloR)
        library(SummarizedExperiment)
        library(scater)
        library(scran)
        library(dplyr)
        library(patchwork)
        library(BiocParallel)
        library(ggplot2)
        
        # Set up parallel execution parameters
        bpparam <- SerialParam()
        
        # Read user input files from the working directory
        pbmc.sce <- readRDS("pbmc.sce")
        pbmc.design <- readRDS("pbmc.design")
        
        # Extract column names dynamically from pbmc.design
        sample_col <- colnames(pbmc.design)[1]
        fixed_col <- colnames(pbmc.design)[2]
        random_col <- colnames(pbmc.design)[3]
        
        # 1. Create Milo object
        pbmc.milo <- Milo(pbmc.sce)
        reducedDim(pbmc.milo, "UMAP") <- reducedDim(pbmc.sce, "UMAP")
        
        # 2. Build KNN graph
        pbmc.milo <- buildGraph(pbmc.milo, k = 60, d = 30)
        
        # 3. Define representative neighbourhoods
        pbmc.milo <- makeNhoods(pbmc.milo, prop = 0.05, k = 60, d=30, refined = TRUE, refinement_scheme="graph")
        
        # 4. Count cells in neighbourhoods
        pbmc.milo <- countCells(pbmc.milo, meta.data = data.frame(colData(pbmc.milo)), samples=sample_col)
        
        # Align rownames of pbmc.design with columns of nhoodCounts(pbmc.milo)
        rownames(pbmc.design) <- as.character(pbmc.design[[sample_col]])
        pbmc.design <- pbmc.design[colnames(nhoodCounts(pbmc.milo)), , drop=FALSE]
        
        # 5. Check for perfect separation
        separated_nhoods <- which(checkSeparation(pbmc.milo, design.df=pbmc.design, condition=fixed_col, min.val=10))
        write.csv(data.frame(Separated_Nhoods = separated_nhoods), "separated_nhoods.csv", row.names=FALSE)
        
        # 6. Test for differential abundance using GLMM
        design_formula <- as.formula(paste0("~ ", fixed_col, " + (1|", random_col, ")"))
        da_results <- testNhoods(pbmc.milo, design = design_formula, design.df = pbmc.design, fdr.weighting="graph-overlap", glmm.solver="Fisher", REML=TRUE, norm.method="TMM", BPPARAM = bpparam, fail.on.error=FALSE)
        
        # Save results to output files
        write.csv(da_results, "da_results.csv", row.names=TRUE)
        saveRDS(pbmc.milo, "pbmc_milo_results.rds")
        
        # Generate diagnostic plots
        pdf("nhood_size_histogram.pdf")
        print(plotNhoodSizeHist(pbmc.milo))
        dev.off()
        
        # Attempt to build neighbourhood graph and plot DA results on UMAP
        tryCatch({
          pbmc.milo <- buildNhoodGraph(pbmc.milo)
          pdf("nhood_da_umap.pdf")
          print(plotNhoodGraphDA(pbmc.milo, da_results, alpha=0.1))
          dev.off()
        }, error = function(e) {
          message("Skipping DA UMAP plot generation: ", e\$message)
        })

    writeLines(c(
        '"BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS":',
        paste0('    miloR: ', as.character(packageVersion('miloR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_da_glmm_random_effects.csv versions.yml
    """
}

workflow BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pbmc.sce, pbmc.design ] ]

    main:
    BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS(ch_input)

    emit:
    tables   = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.tables
    plots    = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.plots
    objects  = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.objects
    versions = BIOC_MILOR_DA_GLMM_RANDOM_EFFECTS.out.versions
}
