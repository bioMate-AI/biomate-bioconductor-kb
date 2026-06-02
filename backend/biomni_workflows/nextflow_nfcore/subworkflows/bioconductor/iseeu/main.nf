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

    # --- Data [] ---
    # Key functions: DGEList, assay, colData, filterByExpr, calcNormFactors
    ---------------------------------------------------------------------
    library(airway)
    data(airway)
    library(edgeR)
    y <- DGEList(assay(airway), samples=colData(airway))
    # --- Maplot [] ---
    # Key functions: MAPlot, iSEE
    ---------------------------------------------------------------------
    ma.panel <- MAPlot(PanelWidth=6L)
    app <- iSEE(airway, initial=list(ma.panel))
    # --- Volcanoplot [] ---
    # Key functions: VolcanoPlot, iSEE
    ---------------------------------------------------------------------
    vol.panel <- VolcanoPlot(PanelWidth=6L)
    app <- iSEE(airway, initial=list(vol.panel))
    # --- Matrix [] ---
    # Key functions: estimateDisp, glmQLFit, glmQLFTest, topTags, rowData
    ---------------------------------------------------------------------
    # Creating another comparison, this time by blocking on the cell line
    design.alt <- model.matrix(~cell + dex, y$samples)
    y.alt <- estimateDisp(y, design.alt)
    fit.alt <- glmQLFit(y.alt, design.alt)
    # --- Reprocessedallendata [] ---
    # Key functions: ReprocessedAllenData, logNormCounts, runPCA, runTSNE
    ---------------------------------------------------------------------
    library(scRNAseq)
    sce <- ReprocessedAllenData(assays="tophat_counts")
    library(scater)
    sce <- logNormCounts(sce, exprs_values="tophat_counts")
    # --- Dynamicreduceddimensionplot [] ---
    # Key functions: DynamicReducedDimensionPlot, ReducedDimensionPlot, iSEE
    ---------------------------------------------------------------------
    # Receives a selection from a reduced dimension plot.
    dyn.panel <- DynamicReducedDimensionPlot(Type="UMAP", Assay="logcounts",
        ColumnSelectionSource="ReducedDimensionPlot1", PanelWidth=6L)
    # NOTE: users do not have to manually create this, just
    # --- Dynamicmarkertable [] ---
    # Key functions: DynamicMarkerTable, iSEE
    ---------------------------------------------------------------------
    diff.panel <- DynamicMarkerTable(PanelWidth=8L, Assay="logcounts",
        ColumnSelectionSource="ReducedDimensionPlot1",)
    # Recycling the reduced dimension panel above, adding a saved selection to
    # compare to the active selection.
    # --- Setfeaturesetcommands [] ---
    # Key functions: setFeatureSetCommands, createGeneSetCommands, FeatureSetTable, VolcanoPlot, iSEE
    ---------------------------------------------------------------------
    setFeatureSetCommands(createGeneSetCommands(identifier="ENSEMBL"))
    gset.tab <- FeatureSetTable(Selected="GO:0002576",
        Search="platelet", PanelWidth=6L)
    # This volcano plot will highlight the genes in the selected gene set.
    # --- Isee [] ---
    # Key functions: iSEE, AggregatedDotPlot, runApp
    ---------------------------------------------------------------------
    # --- Isee [] ---
    # Key functions: iSEE, MarkdownBoard, runApp
    ---------------------------------------------------------------------

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
