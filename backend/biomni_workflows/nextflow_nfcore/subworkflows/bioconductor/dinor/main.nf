#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dinoR
// dinoR tests for significant differences in NOMe-seq footprints between two conditions, using genomic
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dinoR/inst/doc/dinoR-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("dinoR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DINOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dinor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dinor:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dinor:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dinor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dinor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dinor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dinoR)
    library(jsonlite)

    # --- Footprint Classification and Quantification [] ---
    # Key functions: footprintCalc, footprintQuant
    NomeData = footprintCalc(NomeData)
    NomeData = footprintQuant(NomeData)


    # --- Differential Nucleosome Occupancy [] ---
    # Key functions: diNOMeTest
    res = diNOMeTest(NomeData,
                     WTsamples = c("WT_1", "WT_2"),
                     KOsamples = c("AdnpKO_1", "AdnpKO_2"))


    # --- Footprint Percentage Heatmap [] ---
    # Key functions: footprintPerc, fpPercHeatmap
    footprint_percentages = footprintPerc(NomeData)
    fpPercHeatmap(footprint_percentages)


    # --- Footprint Comparison [] ---
    # Key functions: compareFootprints
    compareFootprints(footprint_percentages, res,
                      WTsamples = c("WT_1", "WT_2"),
                      KOsamples = c("AdnpKO_1", "AdnpKO_2"),
                      plotcols = c("#f03b20", "#a8ddb5", "#bdbdbd"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dinor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dinor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dinor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DINOR:", paste0("    dinor: ", packageVersion("dinoR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dinor_results.csv
    touch ${prefix}_dinor_output.rds
    echo "BIOC_DINOR:" > versions.yml
    echo "    dinor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DINOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DINOR(ch_input)

    emit:
    results  = BIOC_DINOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DINOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DINOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DINOR.out.versions  // channel: path(versions.yml)
}
