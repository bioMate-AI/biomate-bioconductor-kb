#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cytoKernel
// cytoKernel implements a kernel-based score test to identify differentially expressed features in hig
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cytoKernel/inst/doc/cytoKernel.R
// Upstream  : ComplexHeatmap
// Downstream: none
//
// Install: BiocManager::install("cytoKernel")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CYTOKERNEL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cytokernel"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cytokernel:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cytokernel:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cytokernel_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cytokernel_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cytokernel_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CytoK)
    library(CytoKDEData)
    library(CytoKDEfeatures)
    library(jsonlite)

    # --- CytoK output [] ---
    # Key functions: CytoK, CytoKDEfeatures
    library(cytoKernel)
    # --- Cyto K D E Data [] ---
    # Key functions: CytoKDEData
    CytoKDEData_HD<- CytoKDEData(CytoK_output, by = "features")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cytokernel_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cytokernel_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cytokernel_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CYTOKERNEL:", paste0("    cytokernel: ", packageVersion("cytoKernel"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cytokernel_results.csv
    touch ${prefix}_cytokernel_output.rds
    echo "BIOC_CYTOKERNEL:" > versions.yml
    echo "    cytokernel: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CYTOKERNEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CYTOKERNEL(ch_input)

    emit:
    results  = BIOC_CYTOKERNEL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CYTOKERNEL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CYTOKERNEL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CYTOKERNEL.out.versions  // channel: path(versions.yml)
}
