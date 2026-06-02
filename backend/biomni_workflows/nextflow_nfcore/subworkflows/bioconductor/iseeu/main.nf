#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iSEEu
// iSEEu (the iSEE universe) contains diverse functionality to extend the usage of the iSEE package, in
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iSEEu/inst/doc/iSEEu.R
// Upstream  : BiocStyle, airway, edgeR, scRNAseq, scater
// Downstream: none
//
// Install: BiocManager::install("iSEEu")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISEEU {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iseeu"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iseeu:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iseeu:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iseeu_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iseeu_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iseeu_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iSEEu)
    library(AggregatedDotPlot)
    library(DGEList)
    library(DynamicMarkerTable)
    library(DynamicReducedDimensionPlot)
    library(FeatureSetTable)
    library(MAPlot)
    library(MarkdownBoard)
    library(ReducedDimensionPlot)
    library(ReprocessedAllenData)
    library(VolcanoPlot)
    library(jsonlite)

    # --- Comparison of Log Fold Changes [] ---
    # Key functions: LogFCLogFCPlot, iSEE
    lfc_panel <- LogFCLogFCPlot(
        PanelWidth = 6L,
        YAxis = "alt.logFC",
        YPValueField = "alt.PValue"
    )
    app_lfc <- iSEE(airway, initial = list(lfc_panel))


    # --- Dynamic Dimension Reduction [] ---
    # Key functions: DynamicReducedDimensionPlot, ReducedDimensionPlot, iSEE
    dyn_panel <- DynamicReducedDimensionPlot(
        Type = "UMAP",
        Assay = "logcounts",
        ColumnSelectionSource = "ReducedDimensionPlot1",
        PanelWidth = 6L
    )
    red_panel <- ReducedDimensionPlot(
        PanelId = 1L,
        PanelWidth = 6L
    )
    app_dyn <- iSEE(sce, initial = list(red_panel, dyn_panel))


    # --- Gene Set Enrichment Exploration [] ---
    # Key functions: FeatureSetTable, createGeneSetCommands, setFeatureSetCommands, iSEE
    setFeatureSetCommands(createGeneSetCommands(identifier = "ENSEMBL"))
    gset_tab <- FeatureSetTable(
        Selected = "GO:0002576",
        Search = "platelet",
        PanelWidth = 6L
    )
    app_gset <- iSEE(airway, initial = list(gset_tab))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iseeu_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iseeu_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iseeu_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISEEU:", paste0("    iseeu: ", packageVersion("iSEEu"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iseeu_results.csv
    touch ${prefix}_iseeu_output.rds
    echo "BIOC_ISEEU:" > versions.yml
    echo "    iseeu: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISEEU_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISEEU(ch_input)

    emit:
    results  = BIOC_ISEEU.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISEEU.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISEEU.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISEEU.out.versions  // channel: path(versions.yml)
}
