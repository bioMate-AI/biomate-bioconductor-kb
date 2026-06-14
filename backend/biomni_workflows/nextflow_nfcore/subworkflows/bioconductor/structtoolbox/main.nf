#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: structToolbox — dims_ms_metabolomics_preprocessing_and_pca
// Pre-process raw direct-infusion mass spectrometry (DIMS) metabolomics data using batch correction, missing value filtering, univariate feature filtering, RSD fi
// Input: SE
// Container: quay.io/biocontainers/bioconductor-structtoolbox:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, ggplot2, pmp, structToolbox
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Convert SummarizedExperiment to DatasetExperiment
//  * 2. [Core Analysis] Apply Quality Control-Robust Spline Correction (QC-RSC) for batch correction
//  * 3. [Core Analysis] Filter features by NA count per batch
//  * 4. [Core Analysis] Apply Kruskal-Wallis rank sum test to exclude features not reliably detected across batches
//  * 5. [Core Analysis] Apply Wilcoxon Signed-Rank test to exclude features not representative of biological samples
//  * 6. [Core Analysis] Apply RSD filter to remove features with high analytical variation
//  * 7. [Core Analysis] Apply PQN normalization, KNN imputation, and generalized log (glog) transformation
//  * 8. [Visualization & Output] Perform mean centering and PCA for exploratory visualization

nextflow.enable.dsl = 2

process BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

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
    .bm_deps <- c("structToolbox", "pmp", "ggplot2")
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
        suppressPackageStartupMessages({
          library(structToolbox)
          library(pmp)
          library(ggplot2)
        })
        
        # 1. Read the input SummarizedExperiment object from the working directory
        if (file.exists("SE")) {
          SE <- readRDS("SE")
        } else if (file.exists("SE.rds")) {
          SE <- readRDS("SE.rds")
        } else {
          stop("Error: Input file 'SE' or 'SE.rds' not found in the working directory.")
        }
        
        # 2. Convert SummarizedExperiment to DatasetExperiment and prepare metadata
        DE = as.DatasetExperiment(SE)
        DE\$name = 'MTBLS79'
        DE\$description = 'Converted from SE provided by the pmp package'
        
        # Dynamically assign metadata columns to avoid hardcoding errors with generic data
        meta_cols <- colnames(DE\$sample_meta)
        class_col <- if ("Class" %in% meta_cols) "Class" else meta_cols[1]
        batch_col <- if ("Batch" %in% meta_cols) "Batch" else if (length(meta_cols) >= 2) meta_cols[2] else meta_cols[1]
        rep_col <- if ("Sample_Rep" %in% meta_cols) "Sample_Rep" else if (length(meta_cols) >= 3) meta_cols[3] else meta_cols[1]
    
        DE\$sample_meta\$run_order = 1:nrow(DE)
        Type=as.character(DE\$sample_meta[[class_col]])
        Type[Type != 'QC'] = 'Sample'
        DE\$sample_meta\$Type = factor(Type)
        DE\$sample_meta\$batch_qc = as.character(DE\$sample_meta[[batch_col]])
        DE\$sample_meta\$batch_qc[DE\$sample_meta\$Type=='QC']='QC'
        DE\$sample_meta[[batch_col]] = factor(DE\$sample_meta[[batch_col]])
        DE\$sample_meta\$Type = factor(Type)
        DE\$sample_meta[[class_col]] = factor(DE\$sample_meta[[class_col]])
        DE\$sample_meta\$batch_qc = factor(DE\$sample_meta\$batch_qc)
        
        # 3. Apply Quality Control-Robust Spline Correction (QC-RSC) for batch correction
        M = sb_corr(
          order_col='run_order',
          batch_col=batch_col, 
          qc_col='Type', 
          qc_label='QC',
          spar_lim = c(0.6,0.8) 
        )
        M = model_apply(M,DE)
        
        # 4. Filter features by NA count per batch
        M2 = filter_na_count(
              threshold=3,
              factor_name=batch_col
            )
        M2 = model_apply(M2,predicted(M))
        
        # 5. Apply Kruskal-Wallis rank sum test to exclude features not reliably detected across batches
        M3 = kw_rank_sum(
              alpha=0.0001,
              mtc='none',
              factor_names=batch_col,
              predicted='significant'
            ) +
            filter_by_name(
              mode='exclude',
              dimension = 'variable',
              seq_in = 'names', 
              names='seq_fcn',
              seq_fcn=function(x){return(x[,1])}
            )
        M3 = model_apply(M3, predicted(M2))
        
        # 6. Apply Wilcoxon Signed-Rank test to exclude features not representative of biological samples
        M4 = wilcox_test(
              alpha=1e-14,
              factor_names='Type', 
              mtc='none', 
              predicted = 'significant'
            ) +
            filter_by_name(
              mode='exclude',
              dimension='variable',
              seq_in='names', 
              names='place_holder',
              seq_fcn=function(x){return(x\$significant)}
            )
        M4 = model_apply(M4, predicted(M3))
        
        # 7. Apply RSD filter to remove features with high analytical variation
        M5 = rsd_filter(
             rsd_threshold=20,
             factor_name='Type'
        )
        M5 = model_apply(M5,predicted(M4))
        
        # 8. Apply PQN normalization, KNN imputation, and generalized log (glog) transformation
        M6 = pqn_norm(qc_label='QC',factor_name='Type') + 
             knn_impute(neighbours=5) +
             glog_transform(qc_label='QC',factor_name='Type')
        M6 = model_apply(M6,predicted(M5))
        
        # 9. Perform mean centering and PCA for exploratory visualization
        M7  = mean_centre() + PCA(number_components = 2)
        M7 = model_apply(M7,predicted(M6))
        
        # 10. Generate PCA scores plot
        C = pca_scores_plot(factor_name=unique(c(rep_col, class_col)),ellipse='none')
        p = chart_plot(C,M7[2]) + coord_fixed() + guides(colour='none')
        
        # 11. Save outputs to the working directory
        # Save the final pre-processed DatasetExperiment object
        saveRDS(predicted(M6), "processed_dataset.rds")
        
        # Save the PCA model sequence object
        saveRDS(M7, "pca_model_sequence.rds")
        
        # Save PCA scores and loadings as CSV files
        write.csv(as.data.frame(M7[2]\$scores\$data), "pca_scores.csv", row.names = TRUE)
        write.csv(as.data.frame(M7[2]\$loadings\$data), "pca_loadings.csv", row.names = TRUE)
        
        # Save the PCA scores plot as a PDF
        pdf("pca_scores_plot.pdf", width = 7, height = 6)
        print(p)
        dev.off()
        
        cat("Pipeline completed successfully. Outputs saved to the working directory.\n")

    writeLines(c(
        '"BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA":',
        paste0('    structToolbox: ', as.character(packageVersion('structToolbox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dims_ms_metabolomics_preprocessing_and_pca.csv versions.yml
    """
}

workflow BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SE ] ]

    main:
    BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA(ch_input)

    emit:
    tables   = BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA.out.tables
    plots    = BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA.out.plots
    objects  = BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA.out.objects
    versions = BIOC_STRUCTTOOLBOX_DIMS_MS_METABOLOMICS_PREPROCESSING_AND_PCA.out.versions
}
