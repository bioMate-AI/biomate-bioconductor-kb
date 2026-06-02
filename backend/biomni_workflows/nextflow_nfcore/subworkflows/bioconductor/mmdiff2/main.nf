#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MMDiff2
// This package detects statistically significant differences between read enrichment profiles in diffe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MMDiff2/inst/doc/MMDiff2.R
// Upstream  : MMDiffBamSubset, MotifDb
// Downstream: none
//
// Install: BiocManager::install("MMDiff2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MMDIFF2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mmdiff2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mmdiff2:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mmdiff2:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mmdiff2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mmdiff2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mmdiff2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DBAmmd)
    library(Samples)
    library(jsonlite)

    # --- DBAmmd analysis [] ---
    # Key functions: DBAmmd, setRegions, getPeakReads, estimateFragmentCenters, compHists, plotPeak, query, compDists
    MMD <- compPvals(MMD,dist.method='MMD')
    plotDists(MMD, dist.method='MMD',whichContrast=1,
    res <- reportResults(MMD)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mmdiff2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mmdiff2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mmdiff2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MMDIFF2:", paste0("    mmdiff2: ", packageVersion("MMDiff2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mmdiff2_results.csv
    touch ${prefix}_mmdiff2_output.rds
    echo "BIOC_MMDIFF2:" > versions.yml
    echo "    mmdiff2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MMDIFF2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MMDIFF2(ch_input)

    emit:
    results  = BIOC_MMDIFF2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MMDIFF2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MMDIFF2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MMDIFF2.out.versions  // channel: path(versions.yml)
}
