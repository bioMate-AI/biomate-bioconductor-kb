#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Doscheda
// Doscheda focuses on quantitative chemoproteomics used to determine protein interaction profiles of s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Doscheda/inst/doc/Doscheda.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Doscheda")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DOSCHEDA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-doscheda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-doscheda:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-doscheda:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_doscheda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_doscheda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_doscheda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Doscheda)
    library(jsonlite)

    # --- Dataset Loading [] ---
    # Key functions: setData
    channelNames <- c(
        "Abundance..F1..126..Control..REP_1",
        "Abundance..F1..127..Sample..REP_1",
        "Abundance..F2..126..Control..REP_2",
        "Abundance..F2..127..Sample..REP_2"
    )
    ex <- doscheda::setData(
        x = ex, dataFrame = Doscheda::doschedaData,
        dataChannels = channelNames,
        accessionChannel = "Master.Protein.Accessions",
        sequenceChannel = 'Sequence',
        qualityChannel = "Qvality.PEP"
    )


    # --- Peptide Filtering and Normalisation [] ---
    # Key functions: removePeptides, runNormalisation, fitModel
    ex <- doscheda::removePeptides(ex, removePeps = FALSE)
    ex <- doscheda::runNormalisation(ex)
    ex <- doscheda::fitModel(ex)


    # --- Diagnostic Plotting [] ---
    # Key functions: corrPlot, pcaPlot, replicatePlot, volcanoPlot
    doscheda::corrPlot(ex)
    doscheda::pcaPlot(ex)
    doscheda::replicatePlot(ex, conc = 0, repIndex1 = 1, repIndex2 = 2)
    doscheda::volcanoPlot(ex)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_doscheda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_doscheda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_doscheda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DOSCHEDA:", paste0("    doscheda: ", packageVersion("Doscheda"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_doscheda_results.csv
    touch ${prefix}_doscheda_output.rds
    echo "BIOC_DOSCHEDA:" > versions.yml
    echo "    doscheda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DOSCHEDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DOSCHEDA(ch_input)

    emit:
    results  = BIOC_DOSCHEDA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DOSCHEDA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DOSCHEDA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DOSCHEDA.out.versions  // channel: path(versions.yml)
}
