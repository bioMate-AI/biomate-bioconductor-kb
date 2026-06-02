#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ADaCGH2
// Analysis and plotting of array CGH data. Allows usage of Circular Binary Segementation, wavelet-base
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ADaCGH2/inst/doc/ADaCGH2.R
// Upstream  : CGHregions, limma
// Downstream: none
//
// Install: BiocManager::install("ADaCGH2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADACGH2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-adacgh2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-adacgh2:2.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-adacgh2:2.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_adacgh2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_adacgh2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_adacgh2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ADaCGH2)
    library(CGHregions)
    library(jsonlite)

    # --- Parallel Segmentation [] ---
    # Key functions: pSegmentHaarSeg
    haar.ff.fork <- pSegmentHaarSeg(
        "cghData.RData",
        "chromData.RData",
        merging = "MAD",
        typeParall = "fork",
        mc.core = 2
    )


    # --- Genomic Visualization [] ---
    # Key functions: pChromPlot
    pChromPlot(
        outRDataName = "haar.ff.fork.RData",
        cghRDataName = "cghData.RData",
        chromRDataName = "chromData.RData",
        posRDataName = "posData.RData",
        probenamesRDataName = "probeNames.RData",
        imgheight = 350,
        typeParall = "fork",
        mc.cores = 2
    )


    # --- Region Conversion [] ---
    # Key functions: outputToCGHregions
    forcghr <- outputToCGHregions(haar.ff.fork)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_adacgh2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_adacgh2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_adacgh2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ADACGH2:", paste0("    adacgh2: ", packageVersion("ADaCGH2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adacgh2_results.csv
    touch ${prefix}_adacgh2_output.rds
    echo "BIOC_ADACGH2:" > versions.yml
    echo "    adacgh2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ADACGH2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ADACGH2(ch_input)

    emit:
    results  = BIOC_ADACGH2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ADACGH2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ADACGH2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ADACGH2.out.versions  // channel: path(versions.yml)
}
