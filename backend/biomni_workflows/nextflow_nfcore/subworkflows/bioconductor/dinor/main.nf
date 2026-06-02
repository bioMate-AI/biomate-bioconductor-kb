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

    # --- assays [] ---
    # Key functions: assays
    assays(NomeData)[["reads"]][1, 1]
    # --- fragment classification [] ---
    # Key functions: footprintCalc
    NomeData <- footprintCalc(NomeData)
    # --- fragment classification example [] ---
    # Key functions: assays
    assays(NomeData)[["footprints"]][[1, 1]][1:10]
    # --- fragment class counts [] ---
    # Key functions: footprintQuant, assays
    NomeData <- footprintQuant(NomeData)
    assays(NomeData)[7:12]
    # --- di N O Me Test [] ---
    # Key functions: diNOMeTest

    # --- Custom ggplot2 visualization [] ---
    # Key functions: group_by, summarize, ggplot, geom_bar, facet_grid
    group_by(contrasts, motif, regulated) %>%
    summarize(n = n()) %>%
    ggplot(aes(x = motif, y = n, fill = regulated)) +
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, geom_point, facet_grid, theme_bw, scale_color_manual
    ggplot(res, aes(y = logFC, x = logCPM, col = regulated)) +
    geom_point() +
    facet_grid(~contrasts) +
    # --- footprint Perc [] ---
    # Key functions: footprintPerc, fpPercHeatmap
    footprint_percentages <- footprintPerc(NomeData)
    fpPercHeatmap(footprint_percentages)
    # --- compare Footprints [] ---
    # Key functions: compareFootprints


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
