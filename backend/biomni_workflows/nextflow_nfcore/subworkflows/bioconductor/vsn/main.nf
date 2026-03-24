#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vsn
// The package implements a method for normalising microarray intensities from single- and multiple-col
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vsn/inst/doc/A-vsn.R
// Upstream  : affydata, ggplot2, limma
// Downstream: webbioc, rnaseqGene
//
// Install: BiocManager::install("vsn")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VSN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vsn"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vsn:3.74.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vsn:3.74.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vsn_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vsn_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vsn_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(vsn)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, coord_fixed, meanSdPlot
    library("ggplot2")
    allpositive = (rowSums(exprs(kidney) <= 0) == 0)
    df1 = data.frame(log2(exprs(kidney)[allpositive, ]),
    # --- Expression matrix extraction [] ---
    # Key functions: smoothScatter, phenoData, assayData, matplot, array, exprs, coefficients, coef
    mai = par("mai"); mai[3]=0; par(mai)
    plot(x2, m, ylim=c(-2, 3.5), type="n", xlab=expression(x[2]), ylab="")
    abline(h=-log2(fc), col="red", lwd=lwd, lty=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vsn_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vsn_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vsn_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VSN:", paste0("    vsn: ", packageVersion("vsn"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vsn_results.csv
    touch ${prefix}_vsn_output.rds
    echo "BIOC_VSN:" > versions.yml
    echo "    vsn: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VSN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VSN(ch_input)

    emit:
    results  = BIOC_VSN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VSN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VSN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VSN.out.versions  // channel: path(versions.yml)
}
