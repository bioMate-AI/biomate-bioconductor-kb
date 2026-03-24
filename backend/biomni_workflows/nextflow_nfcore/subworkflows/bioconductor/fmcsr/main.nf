#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: fmcsR
// The fmcsR package introduces an efficient maximum common substructure (MCS) algorithms combined with
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/fmcsR/inst/doc/fmcsR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("fmcsR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FMCSR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fmcsr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fmcsr:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fmcsr:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fmcsr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fmcsr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fmcsr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(fmcsR)
    library(jsonlite)

    # --- fmcs [] ---
    # Key functions: fmcs, plotMCS
    test <- fmcs(fmcstest[1], fmcstest[2], au=2, bu=1)
    plotMCS(test,regenCoords=TRUE)
    # --- plot M C S [] ---
    # Key functions: plotMCS
    plotMCS(fmcs(sdfset[1], sdfset[2], au=0, bu=0))
    # --- Hierarchical clustering [] ---
    # Key functions: hclust
    d <- sapply(cid(sdf), function(x) fmcsBatch(sdf[x], sdf, au=0, bu=0, matching.mode="aromatic")[,"Overlap_Coefficient"])
    hc <- hclust(as.dist(1-d), method="complete")
    plot(as.dendrogram(hc), edgePar=list(col=4, lwd=2), horiz=TRUE)
    # --- plot M C S [] ---
    # Key functions: plotMCS
    plotMCS(fmcs(sdf[3], sdf[7], au=0, bu=0, matching.mode="aromatic"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fmcsr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fmcsr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fmcsr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FMCSR:", paste0("    fmcsr: ", packageVersion("fmcsR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fmcsr_results.csv
    touch ${prefix}_fmcsr_output.rds
    echo "BIOC_FMCSR:" > versions.yml
    echo "    fmcsr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FMCSR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FMCSR(ch_input)

    emit:
    results  = BIOC_FMCSR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FMCSR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FMCSR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FMCSR.out.versions  // channel: path(versions.yml)
}
