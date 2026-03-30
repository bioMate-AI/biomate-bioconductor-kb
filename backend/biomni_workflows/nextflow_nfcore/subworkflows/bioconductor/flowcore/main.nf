#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowCore
// Provides S4 data structures and basic functions to deal with flow cytometry data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowCore/inst/doc/HowTo-flowCore.R
// Upstream  : Rgraphviz, flowStats, flowWorkspace, ggcyto, gridExtra
// Downstream: flowBeads, flowBin, flowClean, flowCut, flowFP
//
// Install: BiocManager::install("flowCore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowcore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowcore:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowcore:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowcore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowcore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowcore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowCore)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: compensate, getData, fsApply, gs_pop_add, recompute
    if(require(openCyto)){
    thisData <- getData(gs, "nonDebris") #get parent data
    singlet_gate <- fsApply(thisData,
    # --- Quality control and filtering [] ---
    # Key functions: phenoData, pData
    phenoData(fs)$Filename <- fsApply(fs,keyword, "$FIL")
    pData(phenoData(fs))
    # --- Keyword analysis [] ---
    # Key functions: keyword, sample, sampleNames, fsApply, autoplot, spillover, compensate, estimateLogicle
    qg <- quadGate("B710-A" = 2000, "R780-A" = 3000)
    gs_pop_add(gs, qg, parent="CD3", names = c("CD8", "DPT", "CD4", "DNT"))
    gs_pop_get_children(gs[[1]], "CD3")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowcore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowcore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowcore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCORE:", paste0("    flowcore: ", packageVersion("flowCore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowcore_results.csv
    touch ${prefix}_flowcore_output.rds
    echo "BIOC_FLOWCORE:" > versions.yml
    echo "    flowcore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCORE(ch_input)

    emit:
    results  = BIOC_FLOWCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCORE.out.versions  // channel: path(versions.yml)
}
