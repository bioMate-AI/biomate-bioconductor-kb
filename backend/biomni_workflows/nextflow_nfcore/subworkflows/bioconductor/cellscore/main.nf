#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CellScore
// The CellScore package contains functions to evaluate the cell identity of a test sample, given a cel
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CellScore/inst/doc/CellScoreVignette.R
// Upstream  : Biobase, hgu133plus2CellScore, knitr
// Downstream: none
//
// Install: BiocManager::install("CellScore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLSCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellscore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellscore:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellscore:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellscore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellscore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellscore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BoxplotCellScore)
    library(PcaStandards)
    library(PlotCosineSimHeatmap)
    library(RugplotCellScore)
    library(ScatterplotCellScoreComponents)
    library(jsonlite)

    # --- label='HeatmapCode' [] ---
    # Key functions: PlotCosineSimHeatmap
    PlotCosineSimHeatmap(cs.sel, "piPS", width=10, height=10, x=-10, y=3)
    # --- label='PcaCode' [] ---
    # Key functions: PcaStandards

    # --- label='Pca' [] ---
    # Key functions: PcaStandards

    # --- label='ScatterplotCode' [] ---
    # Key functions: ScatterplotCellScoreComponents
    ScatterplotCellScoreComponents(cellscore, cell.change, FALSE)
    # --- label='Scatterplot' [] ---
    # Key functions: ScatterplotCellScoreComponents
    ScatterplotCellScoreComponents(cellscore, cell.change, FALSE)
    # --- label='Boxplot' [] ---
    # Key functions: BoxplotCellScore
    BoxplotCellScore(cellscore, cell.change)
    # --- label='RugplotCode' [] ---
    # Key functions: RugplotCellScore
    RugplotCellScore(cellscore, cell.change, secondary.property)
    # --- label='Rugplot' [] ---
    # Key functions: RugplotCellScore
    RugplotCellScore(cellscore, cell.change, secondary.property)
    # --- label='ReportFig1' [] ---
    # Key functions: scatterplotDonorTargetTest
    mat <- matrix(c(1,1,2,2), nrow=1, ncol=4, byrow=TRUE)
    layout(mat)
    scatterplotDonorTargetTest(test.data, cellscore, FALSE)
    # --- label='ReportFig2' [] ---
    # Key functions: rugplotDonorTargetTest
    mat <- matrix(c(1,1,1,2,2,2), nrow=2, ncol=3, byrow=TRUE)
    layout(mat)
    rugplotDonorTargetTest(test.data, cellscore)
    # --- label='ReportFig3' [] ---
    # Key functions: assayDataElement, heatmapOnOffMarkers
    mat <- matrix(c(1,1,1,1,1,1), nrow=2, ncol=3, byrow=TRUE)
    layout(mat)
    calls <- assayDataElement(eset, "calls")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellscore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellscore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellscore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLSCORE:", paste0("    cellscore: ", packageVersion("CellScore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellscore_results.csv
    touch ${prefix}_cellscore_output.rds
    echo "BIOC_CELLSCORE:" > versions.yml
    echo "    cellscore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLSCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLSCORE(ch_input)

    emit:
    results  = BIOC_CELLSCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLSCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLSCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLSCORE.out.versions  // channel: path(versions.yml)
}
