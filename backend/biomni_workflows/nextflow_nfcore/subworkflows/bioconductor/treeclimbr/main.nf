#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: treeclimbR
// The arrangement of hypotheses in a hierarchical structure appears in many research fields and often 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/treeclimbR/inst/doc/treeclimbR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("treeclimbR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TREECLIMBR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-treeclimbr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-treeclimbr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-treeclimbr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_treeclimbr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_treeclimbr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_treeclimbr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(treeclimbR)
    library(jsonlite)

    # --- Node Aggregation and Differential Abundance [] ---
    # Key functions: showNode, aggTSE, runDA
    all_node <- showNode(tree = rowTree(da_lse), only.leaf = FALSE)
    da_tse <- aggTSE(x = da_lse, rowLevel = all_node, rowFun = sum)
    da_res <- runDA(
        da_tse,
        assay = "counts",
        option = "glmQL",
        design = model.matrix(~ group, data = colData(da_tse)),
        contrast = c(0, 1),
        filter_min_count = 0,
        filter_min_prop = 0,
        filter_min_total_count = 15
    )


    # --- Candidate Selection and Evaluation [] ---
    # Key functions: nodeResult, getCand, evalCand, infoCand
    da_tbl <- nodeResult(da_res, n = Inf, type = "DA")
    da_cand <- getCand(
        tree = rowTree(da_tse),
        score_data = da_tbl,
        node_column = "node",
        p_column = "PValue",
        threshold = 0.05,
        sign_column = "logFC",
        message = FALSE
    )
    da_best <- evalCand(
        tree = rowTree(da_tse),
        levels = da_cand$candidate_list,
        score_data = da_tbl,
        node_column = "node",
        p_column = "PValue",
        sign_column = "logFC"
    )
    da_info <- infoCand(object = da_best)


    # --- Performance Evaluation [] ---
    # Key functions: topNodes, fdr, tpr
    da_out <- topNodes(object = da_best, n = Inf, p_value = 0.05)
    fdr_val <- fdr(
        rowTree(da_tse),
        truth = rownames(da_lse)[rowData(da_lse)$Signal],
        found = da_out$node,
        only.leaf = TRUE
    )
    tpr_val <- tpr(
        rowTree(da_tse),
        truth = rownames(da_lse)[rowData(da_lse)$Signal],
        found = da_out$node,
        only.leaf = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_treeclimbr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_treeclimbr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_treeclimbr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TREECLIMBR:", paste0("    treeclimbr: ", packageVersion("treeclimbR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treeclimbr_results.csv
    touch ${prefix}_treeclimbr_output.rds
    echo "BIOC_TREECLIMBR:" > versions.yml
    echo "    treeclimbr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TREECLIMBR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TREECLIMBR(ch_input)

    emit:
    results  = BIOC_TREECLIMBR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TREECLIMBR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TREECLIMBR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TREECLIMBR.out.versions  // channel: path(versions.yml)
}
