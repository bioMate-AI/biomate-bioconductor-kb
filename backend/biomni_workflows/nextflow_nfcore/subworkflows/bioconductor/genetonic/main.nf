#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneTonic
// This package provides functionality to combine the existing pieces of the transcriptome data and res
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneTonic/inst/doc/GeneTonic_manual.R
// Upstream  : AnnotationDbi, DESeq2, igraph, macrophage, magrittr
// Downstream: none
//
// Install: BiocManager::install("GeneTonic")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENETONIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genetonic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genetonic:3.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genetonic:3.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genetonic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genetonic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genetonic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(GeneTonic)
    library(GeneTonicList)
    library(jsonlite)

    # --- Create DESeqDataSet [] ---
    # Key functions: DESeqDataSet
    library("macrophage")
    library("DESeq2")
    data("gse", package = "macrophage")
    # --- Filter by row sum threshold [] ---
    # Key functions: rowSums, estimateSizeFactors, gene_plot, geneinfo_to_html
    head(mosdef::deresult_to_df(res_macrophage_IFNg_vs_naive))
    dds_macrophage <- estimateSizeFactors(dds_macrophage)
    mosdef::gene_plot(dds_macrophage,
    # --- Variance-stabilizing transformation (VST) [] ---
    # Key functions: vst, gs_scores, gs_scoresheat
    vst_macrophage <- vst(dds_macrophage)
    scores_mat <- gs_scores(
    gs_scoresheat(scores_mat,
    # --- Run DESeq2 differential expression [] ---
    # Key functions: DESeq, results
    dds_macrophage <- DESeq(dds_macrophage)
    res_macrophage_IFNg_vs_naive <- results(dds_macrophage,
    contrast = c("condition", "IFNg", "naive"),
    # --- Feature metadata inspection [] ---
    # Key functions: GeneTonic, example, deresult_to_df, rowData, run_topGO, shake_topGOtableResult, get_annotation_orgdb, get_aggrscores
    library("AnnotationDbi")
    de_symbols_IFNg_vs_naive <- mosdef::deresult_to_df(res_macrophage_IFNg_vs_naive, FDR = 0.05)$SYMBOL
    bg_ids <- rowData(dds_macrophage)$SYMBOL[rowSums(counts(dds_macrophage)) > 0]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genetonic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genetonic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genetonic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENETONIC:", paste0("    genetonic: ", packageVersion("GeneTonic"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genetonic_results.csv
    touch ${prefix}_genetonic_output.rds
    echo "BIOC_GENETONIC:" > versions.yml
    echo "    genetonic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENETONIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENETONIC(ch_input)

    emit:
    results  = BIOC_GENETONIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENETONIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENETONIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENETONIC.out.versions  // channel: path(versions.yml)
}
