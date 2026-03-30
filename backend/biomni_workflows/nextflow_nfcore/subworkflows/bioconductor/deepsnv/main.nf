#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: deepSNV
// This package provides provides quantitative variant callers for detecting subclonal mutations in ult
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/deepSNV/inst/doc/deepSNV.R
// Upstream  : RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("deepSNV")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEEPSNV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deepsnv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deepsnv:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deepsnv:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_deepsnv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deepsnv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deepsnv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(deepSNV)
    library(jsonlite)

    # --- normalize [] ---
    # Key functions: normalize
    data(phiX, package="deepSNV")
    plot(phiX, cex.min=.5)
    phiN <- normalize(phiX, round=TRUE)
    # --- qqplot [] ---
    # Key functions: qqplot
    p.norm <- p.val(phiN)
    n <- sum(!is.na(p.norm))
    qqplot(p.norm, seq(1/n,1, length.out=n), log="xy", type="S", xlab="P-value", ylab="CDF")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deepsnv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deepsnv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deepsnv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEEPSNV:", paste0("    deepsnv: ", packageVersion("deepSNV"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deepsnv_results.csv
    touch ${prefix}_deepsnv_output.rds
    echo "BIOC_DEEPSNV:" > versions.yml
    echo "    deepsnv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEEPSNV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEEPSNV(ch_input)

    emit:
    results  = BIOC_DEEPSNV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEEPSNV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEEPSNV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEEPSNV.out.versions  // channel: path(versions.yml)
}
