#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CytoML
// Uses platform-specific implemenations of the GatingML2.0 standard to exchange gated cytometry data w
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CytoML/inst/doc/HowToExportGatingSet.R
// Upstream  : flowWorkspace, ggcyto, ncdfFlow, openCyto
// Downstream: none
//
// Install: BiocManager::install("CytoML")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOML {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytoml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytoml:2.18.3--r44_0' :
        'quay.io/biocontainers/bioconductor-cytoml:2.18.3--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_cytoml_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytoml_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytoml_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CytoML)
    library(jsonlite)

    # --- Spillover [] ---
    # Key functions: spillover, compensation, compensate, flowjo_biexp_trans, transformerList, transform
    ---------------------------------------------------------------------
    #compensate
    comp <- spillover(fs[[1]])[["SPILL"]]
    chnls <- colnames(comp)
    comp <- compensation(comp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytoml_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytoml_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytoml_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOML:", paste0("    cytoml: ", packageVersion("CytoML"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytoml_results.csv
    touch ${prefix}_cytoml_output.rds
    echo "BIOC_CYTOML:" > versions.yml
    echo "    cytoml: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_CYTOML(ch_input)

    emit:
    results  = BIOC_CYTOML.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOML.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOML.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOML.out.versions  // channel: path(versions.yml)
}
