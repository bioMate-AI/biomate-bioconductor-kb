#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mosdef
// This package provides functionality to run a number of tasks in the differential expression analysis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mosdef/inst/doc/mosdef_userguide.R
// Upstream  : AnnotationDbi, DESeq2, ggplot2, macrophage, topGO
// Downstream: none
//
// Install: BiocManager::install("mosdef")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOSDEF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mosdef"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mosdef:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mosdef:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mosdef_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mosdef_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mosdef_plots.pdf"),    emit: plots, optional: true
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
    library(FoldChange)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: DESeqDataSet
    suppressPackageStartupMessages({
      library("macrophage")
      library("DESeq2")
      library("org.Hs.eg.db")
    })
    # --- Processdata [] ---
    # Key functions: rowSums, counts, DESeq, results
    keep <- rowSums(counts(dds_macrophage) >= 10) >= 6
    dds_macrophage <- dds_macrophage[keep, ]
    dds_macrophage <- DESeq(dds_macrophage)
    # --- Addsymbols [] ---
    # Key functions: mapIds
    res_macrophage_IFNg_vs_naive$symbol <-
    # --- Checkfunctions [] ---
    # Key functions: mosdef_de_container_check, mosdef_res_check
    mosdef_de_container_check(dds_macrophage)
    mosdef_res_check(res_macrophage_IFNg_vs_naive)
    # --- Runtopgo [] ---
    # Key functions: run_topGO
    library("topGO")
    # --- Rungoseq [] ---
    # Key functions: run_goseq, of

    # --- Resultsclupro [] ---
    # Key functions: data
    data(res_enrich_macrophage_cluPro, package = "mosdef")
    # --- Topgoalt [] ---
    # Key functions: deresult_to_df, run_topGO
    res_subset <- deresult_to_df(res_macrophage_IFNg_vs_naive)[1:100, ]
    myde <- res_subset$id
    myassayed <- rownames(res_macrophage_IFNg_vs_naive)
    ## Here keys are Ensembl not symbols
    # --- Geneplot [] ---
    # Key functions: gene_plot
    gene_plot(
      de_container = dds_macrophage,
      gene = "ENSG00000125347",
      intgroup = "condition"
    )
    # --- Volcanoplot [] ---
    # Key functions: de_volcano

    # --- Volcanocustom [] ---
    # Key functions: ggtitle, ylab, xlab, FoldChange
    library("ggplot2")
    volcPlot +
      ggtitle("macrophage Volcano") +
      ylab("-log10 PValue") +
      xlab("Log 2 FoldChange (Cutoff 1/-1)")
    # --- Volcanogo [] ---
    # Key functions: go_volcano

    # --- Maplot [] ---
    # Key functions: plot_ma
    maplot <- plot_ma(
      res_de = res_macrophage_IFNg_vs_naive,
      FDR = 0.05,
      hlines = 1
    )
    # --- Maplotannotated [] ---
    # Key functions: plot_ma

    # --- Runbuttonifier [] ---
    # Key functions: deresult_to_df, buttonifier
    # creating a smaller subset for visualization purposes and to keep the main res_de
    res_subset <- deresult_to_df(res_macrophage_IFNg_vs_naive, FDR = 0.05)[1:100, ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mosdef_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mosdef_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mosdef_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOSDEF:", paste0("    mosdef: ", packageVersion("mosdef"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mosdef_results.csv
    touch ${prefix}_mosdef_output.rds
    echo "BIOC_MOSDEF:" > versions.yml
    echo "    mosdef: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOSDEF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOSDEF(ch_input)

    emit:
    results  = BIOC_MOSDEF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOSDEF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOSDEF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOSDEF.out.versions  // channel: path(versions.yml)
}
