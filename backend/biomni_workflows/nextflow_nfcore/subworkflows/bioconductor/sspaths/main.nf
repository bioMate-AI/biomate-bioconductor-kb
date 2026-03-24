#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ssPATHS
// This package generates pathway scores from expression data for single samples after training on a re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ssPATHS/inst/doc/ssPATHS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ssPATHS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSPATHS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sspaths"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sspaths:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sspaths:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sspaths_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sspaths_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sspaths_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Summarizedexperiment [] ---
    # Key functions: SummarizedExperiment, colData
    tcga_se <- SummarizedExperiment(t(tcga_expr_df[ , -(1:4)]),
                                    colData=tcga_expr_df[ , 2:4])
    colnames(tcga_se) <- tcga_expr_df$tcga_id
    colData(tcga_se)$sample_id <- tcga_expr_df$tcga_id
    # --- Get Hypoxia Genes [] ---
    # Key functions: get_hypoxia_genes, intersect
    hypoxia_gene_ids <- get_hypoxia_genes()
    hypoxia_gene_ids <- intersect(hypoxia_gene_ids, rownames(tcga_se))
    # --- Coldata [] ---
    # Key functions: colData, ifelse
    colData(tcga_se)$Y <- ifelse(colData(tcga_se)$is_normal, 0, 1)
    # --- Get Gene Weights [] ---
    # Key functions: get_gene_weights
    res <- get_gene_weights(tcga_se, hypoxia_gene_ids, unidirectional=TRUE)
    gene_weights <- res[[1]]
    sample_scores <- res[[2]]
    # --- Get Classification Accuracy [] ---
    # Key functions: get_classification_accuracy
    training_res <- get_classification_accuracy(sample_scores, positive_val=1)
    # plot the ROC curve
    plot(training_res[[4]], col="blue", ylim=c(0, 1))
    roc_text <- paste("AUC:", round(training_res$auc_roc,3))
    legend(0.1,0.8, roc_text,
    # --- Data [] ---
    # Key functions: SummarizedExperiment, colData, get_new_samp_score
    data(new_samp_df)
    new_samp_se <- SummarizedExperiment(t(new_samp_df[ , -(1)]),
                                        colData=new_samp_df[ , 1, drop=FALSE])
    colnames(colData(new_samp_se)) <- "sample_id"
    new_score_df <- get_new_samp_score(gene_weights, new_samp_se)
    # --- Function [] ---
    # Key functions: ggplot, aes, geom_boxplot, theme
    plot_scores <- function(hif_scores){
        # format the sample IDS
        hif_scores$sample_type <- substr(hif_scores$sample_id, 1,
                                      nchar((hif_scores$sample_id))-2)
        colnames(hif_scores)[2] <- "pathway_score"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sspaths_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sspaths_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sspaths_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SSPATHS:", paste0("    sspaths: ", packageVersion("ssPATHS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sspaths_results.csv
    touch ${prefix}_sspaths_output.rds
    echo "BIOC_SSPATHS:" > versions.yml
    echo "    sspaths: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SSPATHS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SSPATHS(ch_input)

    emit:
    results  = BIOC_SSPATHS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SSPATHS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SSPATHS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SSPATHS.out.versions  // channel: path(versions.yml)
}
