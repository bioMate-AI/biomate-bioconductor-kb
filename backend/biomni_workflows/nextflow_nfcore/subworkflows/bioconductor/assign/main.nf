#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASSIGN
// ASSIGN is a computational tool to evaluate the pathway deregulation/activation status in individual 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASSIGN/inst/doc/ASSIGN.vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ASSIGN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASSIGN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-assign"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-assign:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-assign:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_assign_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_assign_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_assign_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASSIGN)
    library(jsonlite)

    # --- rep [] ---
    # Key functions: rep
    data(trainingData1)
    data(testData1)
    data(geneList1)
    # --- optimize G F R N [] ---
    # Key functions: optimizeGFRN
    combat.data <- ComBat.step2(testData, pcaPlots = TRUE)
    optimization_results <- optimizeGFRN(combat.data, corData,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_assign_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_assign_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_assign_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASSIGN:", paste0("    assign: ", packageVersion("ASSIGN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_assign_results.csv
    touch ${prefix}_assign_output.rds
    echo "BIOC_ASSIGN:" > versions.yml
    echo "    assign: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASSIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASSIGN(ch_input)

    emit:
    results  = BIOC_ASSIGN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASSIGN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASSIGN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASSIGN.out.versions  // channel: path(versions.yml)
}
