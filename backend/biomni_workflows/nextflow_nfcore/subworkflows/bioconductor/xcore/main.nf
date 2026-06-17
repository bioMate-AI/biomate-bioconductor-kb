#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: xcore — tf_activity_modeling
// Model transcription factor activity from promoter expression counts and molecular signatures using ridge regression.
// Input: counts.csv, design_matrix.csv
// Container: quay.io/biocontainers/bioconductor-xcore:1.14.0--r45hdfd78af_0
// R packages: BiocParallel, AnnotationHub, doParallel, ExperimentHub, pheatmap, xcore
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, ExperimentHub, doParallel, pheatmap, xcore
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare counts for regression and set baseline level using prepareCountsForRegression
//  * 2. [Input & Preparation] Load molecular signatures from xcoredata via ExperimentHub
//  * 3. [Core Analysis] Add signatures to the MultiAssayExperiment object using addSignatures
//  * 4. [Core Analysis] Filter out signatures overlapping too few or too many promoters using filterSignatures
//  * 5. [Core Analysis] Register a parallel backend
//  * 6. [Core Analysis] Model gene expression using ridge regression with modelGeneExpression

nextflow.enable.dsl = 2

process BIOC_XCORE_TF_ACTIVITY_MODELING {
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
    .bm_deps <- c("BiocParallel", "AnnotationHub", "doParallel", "ExperimentHub", "pheatmap", "xcore")
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
        library("xcore")
        library("ExperimentHub")
        library("doParallel")
        library("BiocParallel")
        library("pheatmap")
        
        # 1. Read user input files
        # counts.csv: matrix of raw expression counts with promoters as rows and samples as columns
        counts <- as.matrix(read.csv("counts.csv", row.names = 1, check.names = FALSE))
        
        # design_matrix.csv: experimental design matrix mapping samples (rows) to conditions (columns)
        design <- as.matrix(read.csv("design_matrix.csv", row.names = 1, check.names = FALSE))
        
        # Determine the baseline level (first column of the design matrix)
        base_lvl <- colnames(design)[1]
        
        # Prepare counts for regression
        mae <- prepareCountsForRegression(counts = counts,
                                          design = design,
                                          base_lvl = base_lvl)
        
        # 2. Load molecular signatures from xcoredata via ExperimentHub
        eh <- ExperimentHub()
        remap_promoters_f5 <- eh[["EH7301"]]
        
        # 3. Add signatures to the MultiAssayExperiment object
        mae <- addSignatures(mae, remap = remap_promoters_f5)
        
        # 4. Filter out signatures overlapping too few or too many promoters
        mae <- filterSignatures(mae, min = 0.05, max = 0.95)
        
        # 5. Register a parallel backend
        doParallel::registerDoParallel(2L)
        BiocParallel::register(BiocParallel::DoparParam(), default = TRUE)
        
        # 6. Model gene expression using ridge regression
        set.seed(314159265)
        res <- modelGeneExpression(
          mae = mae,
          xnames = "remap",
          nfolds = 5)
        
        # Save the complete results object
        saveRDS(res, file = "tf_activity_results.rds")
        
        # Save the table of molecular signatures and their activities
        write.csv(res\$results\$remap, file = "remap_results.csv", row.names = FALSE)
        
        # Visualize the top 10 scoring molecular signatures
        top_signatures <- head(res\$results\$remap, 10)
        plot_cols <- setdiff(colnames(design), base_lvl)
        plot_cols <- intersect(plot_cols, colnames(top_signatures))
        
        if (length(plot_cols) > 0 && nrow(top_signatures) > 0) {
          pdf("top_signatures_heatmap.pdf", width = 8, height = 6)
          pheatmap::pheatmap(
            mat = as.matrix(top_signatures[, plot_cols, drop = FALSE]),
            scale = "none",
            labels_row = top_signatures\$name,
            cluster_cols = FALSE,
            color = colorRampPalette(c("blue", "white", "red"))(15),
            breaks = seq(from = -0.1, to = 0.1, length.out = 16),
            main = "Molecular signatures activities"
          )
          dev.off()
        }

    writeLines(c(
        '"BIOC_XCORE_TF_ACTIVITY_MODELING":',
        paste0('    xcore: ', as.character(packageVersion('xcore')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tf_activity_modeling.csv versions.yml
    """
}

workflow BIOC_XCORE_TF_ACTIVITY_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.csv, design_matrix.csv ] ]

    main:
    BIOC_XCORE_TF_ACTIVITY_MODELING(ch_input)

    emit:
    tables   = BIOC_XCORE_TF_ACTIVITY_MODELING.out.tables
    plots    = BIOC_XCORE_TF_ACTIVITY_MODELING.out.plots
    objects  = BIOC_XCORE_TF_ACTIVITY_MODELING.out.objects
    versions = BIOC_XCORE_TF_ACTIVITY_MODELING.out.versions
}
