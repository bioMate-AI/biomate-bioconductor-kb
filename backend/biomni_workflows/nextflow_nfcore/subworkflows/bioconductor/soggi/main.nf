#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: soGGi
// The soGGi package provides a toolset to create genomic interval aggregate/summary plots of signal or
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/soGGi/inst/doc/soggi.R
// Upstream  : GenomicRanges, ggplot2
// Downstream: none
//
// Install: BiocManager::install("soGGi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SOGGI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-soggi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-soggi:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-soggi:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_soggi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_soggi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_soggi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRangesList)
    library(jsonlite)

    # --- Normalize protein intensities [] ---
    # Key functions: normalise, plotRegion
    normHighPol <- normalise(c(chipExampleBig$highPol, chipExampleBig$highPol_Rep2), method="quantile",normFactors = 1)
    normMidPol <- normalise(c(chipExampleBig$midPol, chipExampleBig$midPol_Rep2), method="quantile",normFactors = 1)
    normPol <-c(normHighPol$highPol, normHighPol$highPol_Rep2, normMidPol$midPol, normMidPol$midPol_Rep2)
    # --- Genomic ranges list construction [] ---
    # Key functions: regionPlot, rbind, plotRegion, GRangesList, groupByOverlaps
    library(GenomicRanges)
    subsetsCharacter <- list(first25 = (as.vector(rowRanges(chipExampleBig[[1]])$name[1:25])), fourth25 = as.vector(rowRanges(chipExampleBig[[1]])$name[76:100]))
    subsetsGRanges <- GRangesList(low=(rowRanges(chipExampleBig[[1]])[1:25]), high=rowRanges(chipExampleBig[[2]])[76:100])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_soggi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_soggi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_soggi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SOGGI:", paste0("    soggi: ", packageVersion("soGGi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_soggi_results.csv
    touch ${prefix}_soggi_output.rds
    echo "BIOC_SOGGI:" > versions.yml
    echo "    soggi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SOGGI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SOGGI(ch_input)

    emit:
    results  = BIOC_SOGGI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SOGGI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SOGGI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SOGGI.out.versions  // channel: path(versions.yml)
}
