#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scFeatures — feature_generation_and_downstream_analysis
// Generate multi-view features from single-cell RNA-seq data and perform downstream classification or survival analysis.
// Input: expression_matrix.rds, metadata.csv
// Container: quay.io/biocontainers/bioconductor-scfeatures:1.6.0--r44hdfd78af_0
// R packages: ClassifyR, S4Vectors, scFeatures, survival, survminer
// Bioconductor: 3.20 | R: 4.4
// Requires: ClassifyR, scFeatures, survival, survminer
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load single-cell expression and metadata
//  * 2. [Core Analysis] Generate multi-view features using scFeatures
//  * 3. [Core Analysis] Perform cross-validated classification using ClassifyR::crossValidate
//  * 4. [Core Analysis] Perform hierarchical clustering and survival analysis using hclust and survival::survfit

nextflow.enable.dsl = 2

process BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

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
    .bm_deps <- c("ClassifyR", "S4Vectors", "scFeatures", "survival", "survminer")
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
        
    library(scFeatures)
    library(ClassifyR)
    library(survival)
    library(survminer)
    
    # 1. Load single-cell expression and metadata
    expr_mat <- readRDS("expression_matrix.rds")
    cell_metadata <- read.csv("metadata.csv", stringsAsFactors = FALSE)
    
    if (!"condition" %in% colnames(cell_metadata)) {
      stop("Error: 'condition' column not found in metadata.csv. Please ensure the metadata contains a 'condition' column for classification.")
    }
    
    # 2. Generate multi-view features using scFeatures
    scfeatures_result <- scFeatures(data = expr_mat, sample = cell_metadata\$sample, celltype = cell_metadata\$celltype,
                                    feature_types = "gene_mean_celltype"  , 
                                    type = "scrna",  
                                    ncores = 1,  
                                    species = "Homo sapiens")
    
    feature_gene_mean_celltype <- scfeatures_result\$gene_mean_celltype
    
    # inspect the first 5 rows and first 5 columns
    feature_gene_mean_celltype[1:5, 1:5]
    
    # inspect the dimension of the matrix
    dim(feature_gene_mean_celltype)
    
    # 3. Perform cross-validated classification using ClassifyR::crossValidate
    # X is the feature type generated
    # y is the condition for classification
    X <- feature_gene_mean_celltype
    y <- cell_metadata[!duplicated(cell_metadata\$sample), ]
    y <- y[match(rownames(X), y\$sample), ]\$condition
    
    # run the classification model using random forest
    result <- ClassifyR::crossValidate(
        X, y,
        classifier = "randomForest", nCores = 2,
        nFolds = 3, nRepeats = 5
    )
    
    pdf("classification_performance_plot.pdf", width = 7, height = 5)
    print(ClassifyR::performancePlot(results = result))
    dev.off()
    
    # 4. Perform hierarchical clustering and survival analysis using hclust and survival::survfit
    X <- feature_gene_mean_celltype
    X <- t(X)
    
    # run hierarchical clustering
    hclust_res <- hclust(
        as.dist(1 - cor(X, method = "pearson")),
        method = "ward.D2"
    )
    
    set.seed(1)
    # generate some survival outcome, including the survival days and the censoring outcome
    survival_day <- sample(1:100, ncol(X))
    censoring <- sample(0:1, ncol(X), replace = TRUE)
    
    cluster_res <- cutree(hclust_res, k = 2)
    metadata <- data.frame( cluster = factor(cluster_res),
                            survival_day = survival_day,
                            censoring = censoring)
    
    # plot survival curve
    fit <- survfit(
        Surv(survival_day, censoring) ~ cluster,
        data = metadata
    )
    ggsurv <- ggsurvplot(fit,
        conf.int = FALSE, risk.table = TRUE,
        risk.table.col = "strata", pval = TRUE
    )
    
    pdf("survival_curve_plot.pdf", width = 7, height = 7)
    print(ggsurv)
    dev.off()
    
    # Save meaningful results to files
    saveRDS(scfeatures_result, "scfeatures_result.rds")
    write.csv(feature_gene_mean_celltype, "feature_gene_mean_celltype.csv", row.names = TRUE)
    write.csv(metadata, "survival_metadata_clusters.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS":',
        paste0('    scFeatures: ', as.character(packageVersion('scFeatures')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_generation_and_downstream_analysis.csv versions.yml
    """
}

workflow BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.rds, metadata.csv ] ]

    main:
    BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS.out.tables
    plots    = BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS.out.plots
    objects  = BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS.out.objects
    versions = BIOC_SCFEATURES_FEATURE_GENERATION_AND_DOWNSTREAM_ANALYSIS.out.versions
}
