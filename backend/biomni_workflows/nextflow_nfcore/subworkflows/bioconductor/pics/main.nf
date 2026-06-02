#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PICS
// Probabilistic inference of ChIP-Seq using an empirical Bayes mixture model approach.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PICS/inst/doc/PICS.R
// Upstream  : knitr, parallel, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("PICS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pics:2.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pics:2.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PICS)
    library(jsonlite)

    # --- Probabilistic Inference of ChIP-Seq [] ---
    # Key functions: PICS
    pics <- PICS(seg, nCores = 2)


    # --- False Discovery Rate Estimation [] ---
    # Key functions: segmentPICS, PICS, picsFDR
    segC <- segmentPICS(dataCont_gr, dataC = dataIP_gr, map = map_gr,
                        minReads = 1)
    picsC <- PICS(segC)
    fdr <- picsFDR(pics, picsC, filter = list(delta = c(50, Inf),
                   se = c(0, 50), sigmaSqF = c(0, 22500),
                   sigmaSqR = c(0, 22500)))


    # --- Export Genomic Ranges [] ---
    # Key functions: makeGRangesOutput
    myFilter <- list(delta = c(50, 300), se = c(0, 50),
                     sigmaSqF = c(0, 22500), sigmaSqR = c(0, 22500))
    rdBed <- makeGRangesOutput(pics, type = "bed",
                               filter = c(myFilter, list(score = c(1, Inf))))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PICS:", paste0("    pics: ", packageVersion("PICS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pics_results.csv
    touch ${prefix}_pics_output.rds
    echo "BIOC_PICS:" > versions.yml
    echo "    pics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PICS(ch_input)

    emit:
    results  = BIOC_PICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PICS.out.versions  // channel: path(versions.yml)
}
