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
    library(CellScore)
    library(BoxplotCellScore)
    library(PcaStandards)
    library(PlotCosineSimHeatmap)
    library(RugplotCellScore)
    library(ScatterplotCellScoreComponents)
    library(jsonlite)

    # --- On-Off Visualization [] ---
    # Key functions: BarplotOnOff
    barplot.out <- BarplotOnOff(eset, group.OnOff$scores)


    # --- Cosine Similarity Scoring [] ---
    # Key functions: CosineSimScore, PlotCosineSimHeatmap
    cs <- CosineSimScore(eset, cell.change, iqr.cutoff = 0.1)
    PlotCosineSimHeatmap(cs$cosine.general.groups, "general groups",
                         width = 20, height = 20, x = -20, y = 3)
    PlotCosineSimHeatmap(cs$cosine.subgroups, "subgroups",
                         width = 14, height = 14, x = -14, y = 3)


    # --- Standards PCA [] ---
    # Key functions: PcaStandards
    PcaStandards(cs$pdataSub$general_cell_type, "General Cell Type",
                 cs$esetSub.IQR)


    # --- CellScore Calculation and Evaluation [] ---
    # Key functions: CellScore, ScatterplotCellScoreComponents, BoxplotCellScore, RugplotCellScore
    cellscore <- CellScore(data = eset, transitions = cell.change,
                           scores.onoff = individ.OnOff$scores,
                           scores.cosine = cs$cosine.samples)
    ScatterplotCellScoreComponents(cellscore, cell.change, FALSE)
    BoxplotCellScore(cellscore, cell.change)
    RugplotCellScore(cellscore, cell.change,
                     "transition_induction_method")

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
