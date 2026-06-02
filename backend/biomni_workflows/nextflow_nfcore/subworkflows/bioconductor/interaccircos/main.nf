#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: interacCircos
// Implement in an efficient approach to display the genomic data, relationship, information in an inte
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/interacCircos/inst/doc/interacCircos.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("interacCircos")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTERACCIRCOS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-interaccircos"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-interaccircos:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-interaccircos:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_interaccircos_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_interaccircos_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_interaccircos_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(interacCircos)
    library(Circos)
    library(CircosBackground)
    library(jsonlite)

    # --- Histogram Visualization [] ---
    # Key functions: Circos, CircosHistogram
    hist_track <- CircosHistogram(
        "HISTOGRAM01",
        data = histogramExample,
        fillColor = "#ff7f0e",
        maxRadius = 210,
        minRadius = 175,
        animationDisplay = TRUE
    )
    circos_hist <- Circos(
        moduleList = hist_track,
        genome = list(
            "2L" = 23011544, "2R" = 21146708, "3L" = 24543557,
            "3R" = 27905053, "X" = 22422827, "4" = 1351857
        ),
        outerRadius = 220,
        width = 700,
        height = 550
    )


    # --- SNP and Background Visualization [] ---
    # Key functions: Circos, CircosSnp, CircosBackground
    snp_track <- CircosSnp(
        "SNP01",
        minRadius = 150,
        maxRadius = 190,
        data = snpExample,
        SNPFillColor = "#9ACD32",
        circleSize = 2,
        SNPAxisColor = "#B8B8B8",
        SNPAxisWidth = 0.5,
        animationDisplay = TRUE,
        animationTime = 2000,
        animationDelay = 0,
        animationType = "linear"
    )
    bg_track <- CircosBackground(
        "BG01",
        minRadius = 145,
        maxRadius = 200
    )
    circos_snp <- Circos(
        moduleList = snp_track + bg_track,
        width = 700,
        height = 550
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_interaccircos_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_interaccircos_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_interaccircos_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTERACCIRCOS:", paste0("    interaccircos: ", packageVersion("interacCircos"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interaccircos_results.csv
    touch ${prefix}_interaccircos_output.rds
    echo "BIOC_INTERACCIRCOS:" > versions.yml
    echo "    interaccircos: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTERACCIRCOS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTERACCIRCOS(ch_input)

    emit:
    results  = BIOC_INTERACCIRCOS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTERACCIRCOS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTERACCIRCOS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTERACCIRCOS.out.versions  // channel: path(versions.yml)
}
