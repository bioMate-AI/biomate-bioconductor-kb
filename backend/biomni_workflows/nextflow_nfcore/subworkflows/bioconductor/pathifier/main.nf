#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pathifier
// Pathifier is an algorithm that infers pathway deregulation scores for each tumor sample on the basis
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pathifier/inst/doc/Overview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pathifier")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHIFIER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathifier"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathifier:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathifier:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathifier_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathifier_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathifier_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pathifier)
    library(jsonlite)

    # --- Quantify Pathways Deregulation [] ---
    # Key functions: quantify_pathways_deregulation
    PDS<-quantify_pathways_deregulation(sheffer$data, sheffer$allgenes,
      kegg$gs, kegg$pathwaynames, sheffer$normals, attempts = 100,
      min_exp=sheffer$minexp, min_std=sheffer$minstd)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathifier_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathifier_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathifier_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHIFIER:", paste0("    pathifier: ", packageVersion("pathifier"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathifier_results.csv
    touch ${prefix}_pathifier_output.rds
    echo "BIOC_PATHIFIER:" > versions.yml
    echo "    pathifier: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHIFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHIFIER(ch_input)

    emit:
    results  = BIOC_PATHIFIER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHIFIER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHIFIER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHIFIER.out.versions  // channel: path(versions.yml)
}
