#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: martini
// martini deals with the low power inherent to GWAS studies by using prior knowledge represented as a 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/martini/inst/doc/scones_usage.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("martini")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MARTINI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-martini"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-martini:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-martini:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_martini_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_martini_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_martini_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(martini)
    library(jsonlite)

    # --- create GS network [] ---
    # Key functions: get_GS_network
    gs <- get_GS_network(minigwas)
    par(mar=c(0,0,0,0)+.1)
    plot(gs)
    # --- create GM network [] ---
    # Key functions: get_GM_network
    gm <- get_GM_network(minigwas, snpMapping = minisnpMapping)
    par(mar=c(0,0,0,0)+.1)
    plot(gm)
    # --- create GI network [] ---
    # Key functions: get_GI_network
    gi <- get_GI_network(minigwas, snpMapping = minisnpMapping, ppi = minippi)
    par(mar=c(0,0,0,0)+.1)
    plot(gi)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_martini_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_martini_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_martini_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MARTINI:", paste0("    martini: ", packageVersion("martini"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_martini_results.csv
    touch ${prefix}_martini_output.rds
    echo "BIOC_MARTINI:" > versions.yml
    echo "    martini: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MARTINI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MARTINI(ch_input)

    emit:
    results  = BIOC_MARTINI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MARTINI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MARTINI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MARTINI.out.versions  // channel: path(versions.yml)
}
