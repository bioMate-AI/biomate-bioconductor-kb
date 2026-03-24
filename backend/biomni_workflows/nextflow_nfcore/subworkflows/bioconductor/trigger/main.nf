#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: trigger
// This R package provides tools for the statistical analysis of integrative genomic data that involve 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/trigger/inst/doc/trigger.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("trigger")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRIGGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trigger"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trigger:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trigger:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trigger_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trigger_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trigger_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(trigger)
    library(jsonlite)

    # --- Import [] ---
    # Key functions: sample, attach
    library(trigger)
     data(yeast)
     names(yeast)
    #reduce data size for vignette run time
    set.seed(123)
    # --- Build [] ---
    # Key functions: build, detach
    trig.obj <- trigger.build(marker=marker, exp=exp,
    	marker.pos=marker.pos, exp.pos=exp.pos)
    trig.obj
    detach(yeast)
    # --- Link [] ---
    # Key functions: link
    trig.obj = trigger.link(trig.obj, norm = TRUE)
    # --- Mlink [] ---
    # Key functions: loclink, mlink
    trig.obj = trigger.loclink(trig.obj)
    trig.obj = trigger.mlink(trig.obj, B = 10, idx = NULL)
    # --- Eigenr2 [] ---
    # Key functions: eigenR2
    trig.obj = trigger.eigenR2(trig.obj, adjust = FALSE)
    # --- loclink [] ---
    # Key functions: loclink, net
    trig.obj = trigger.loclink(trig.obj, window.size = 10000)
    trig.prob = trigger.net(trig.obj, Bsec = 100, idx = NULL)
     dim(trig.prob)
    # --- export2cross [] ---
    # Key functions: export2cross
    cross = trigger.export2cross(trig.obj, plotarg = FALSE, verbose = FALSE)
    # --- Trait Trigger [] ---
    # Key functions: trait
    causreg = trigger.trait(trig.obj, trait = "DSE1", cross = cross, addplot = TRUE, thr = 3)
    causreg

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trigger_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trigger_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trigger_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRIGGER:", paste0("    trigger: ", packageVersion("trigger"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trigger_results.csv
    touch ${prefix}_trigger_output.rds
    echo "BIOC_TRIGGER:" > versions.yml
    echo "    trigger: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRIGGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRIGGER(ch_input)

    emit:
    results  = BIOC_TRIGGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRIGGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRIGGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRIGGER.out.versions  // channel: path(versions.yml)
}
