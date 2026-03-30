#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: qpcrNorm
// The package contains functions to perform normalization of high-throughput qPCR data. Basic function
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/qpcrNorm/inst/doc/qpcrNorm.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("qpcrNorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QPCRNORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qpcrnorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qpcrnorm:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qpcrnorm:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qpcrnorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qpcrnorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qpcrnorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CV)
    library(jsonlite)

    # --- Loadlib [] ---
    # Key functions: data
    library(qpcrNorm)
    data(qpcrBatch.object)
    # --- Demos4 [] ---
    # Key functions: slotNames
    slotNames(qpcrBatch.object)
    # --- Normr [] ---
    # Key functions: normQpcrRankInvariant
    mynormRI.data <- normQpcrRankInvariant(qpcrBatch.object, 1)
    # --- Normq [] ---
    # Key functions: normQpcrQuantile
    mynormQuant.data <- normQpcrQuantile(qpcrBatch.object)
    # --- Normh [] ---
    # Key functions: normQpcrHouseKeepingGenes
    mynormHK.data <- normQpcrHouseKeepingGenes(qpcrBatch.object, c("Gpx4"))
    # --- Normz [] ---
    # Key functions: normalize
    mynormQuant.data <- normalize(qpcrBatch.object, "quantile")
    mynormHK.data <- normalize(qpcrBatch.object, "housekeepinggenes", c("Gpx4"))
    # --- Qbox [] ---
    # Key functions: frame
    boxplot(data.frame(mynormQuant.data@exprs), names=paste("Time", 1:13, sep=""), col="darkgreen", ylab="Ct Value")
    # --- Cvcalc [] ---
    # Key functions: calcCV
    cvVals <- c(calcCV(qpcrBatch.object), calcCV(mynormHK.data), calcCV(mynormQuant.data), calcCV(mynormRI.data))
    # --- Plotcv [] ---
    # Key functions: CV
    barplot(cvVals*100, col=c("steelblue", "orange", "gold", "orchid4"), ylab="Average CV(%)", beside=TRUE,
    	names=c("Raw", "HK", "Quantile", "Rank-Invariant"))
    	text(c(.75, 1.9, 3.1, 4.3), rep(2,4), round(cvVals*100, 2))
    # --- Plotvarmean [] ---
    # Key functions: plotVarMean
    plotVarMean(mynormQuant.data, mynormHK.data, normTag1="Quantile", normTag2="HK-Gene")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qpcrnorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qpcrnorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qpcrnorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QPCRNORM:", paste0("    qpcrnorm: ", packageVersion("qpcrNorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qpcrnorm_results.csv
    touch ${prefix}_qpcrnorm_output.rds
    echo "BIOC_QPCRNORM:" > versions.yml
    echo "    qpcrnorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QPCRNORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QPCRNORM(ch_input)

    emit:
    results  = BIOC_QPCRNORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QPCRNORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QPCRNORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QPCRNORM.out.versions  // channel: path(versions.yml)
}
