#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: arrayQualityMetrics
// This package generates microarray quality metrics reports for data in Bioconductor microarray data c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/arrayQualityMetrics/inst/doc/aqm.R
// Upstream  : ALLMLL, vsn, CCl4
// Downstream: maEndToEnd
//
// Install: BiocManager::install("arrayQualityMetrics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ARRAYQUALITYMETRICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-arrayqualitymetrics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-arrayqualitymetrics:3.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-arrayqualitymetrics:3.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_arrayqualitymetrics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_arrayqualitymetrics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_arrayqualitymetrics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(arrayQualityMetrics)
    library(jsonlite)


    # --- Dummy1 [] ---
    # Key functions: interactive, cairo, dummy.pdf
    ##options(error=recover)
    options(bitmapType = "cairo")
    .HaveDummy = !interactive()
      if(.HaveDummy) pdf("dummy.pdf")

    # --- Loading [] ---
    # Key functions: arrayQualityMetrics
    library("arrayQualityMetrics")
    library("ALLMLL")
    data("MLL.A")

    # --- Data Preparation [] ---
    # Key functions: prepdata
    preparedData = prepdata(expressionset = MLL.A, 
                            intgroup = c(), 
                            do.logtransform = TRUE)

    # --- Metrics [] ---
    # Key functions: aqm.boxplot, aqm.density
    bo = aqm.boxplot(preparedData)
    de = aqm.density(preparedData)
    qm = list("Boxplot" = bo, "Density" = de)

    # --- Booutliers [] ---
    # Key functions: arrayqualitymetrics
    bo@outliers

    # --- Short Report [] ---
    # Key functions: tempdir, aqm.writereport, pData
    outdir = tempdir()
    aqm.writereport(modules = qm, reporttitle = "My example", outdir = outdir, 
                    arrayTable = pData(MLL.A))
    outdir

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_arrayqualitymetrics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_arrayqualitymetrics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_arrayqualitymetrics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ARRAYQUALITYMETRICS:", paste0("    arrayqualitymetrics: ", packageVersion("arrayQualityMetrics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_arrayqualitymetrics_results.csv
    touch ${prefix}_arrayqualitymetrics_output.rds
    echo "BIOC_ARRAYQUALITYMETRICS:" > versions.yml
    echo "    arrayqualitymetrics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ARRAYQUALITYMETRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ARRAYQUALITYMETRICS(ch_input)

    emit:
    results  = BIOC_ARRAYQUALITYMETRICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ARRAYQUALITYMETRICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ARRAYQUALITYMETRICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ARRAYQUALITYMETRICS.out.versions  // channel: path(versions.yml)
}
