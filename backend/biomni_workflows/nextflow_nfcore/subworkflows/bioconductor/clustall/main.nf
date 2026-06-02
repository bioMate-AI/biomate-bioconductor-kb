#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClustAll
// Data driven strategy to find hidden groups of patients with complex diseases using clinical data. Cl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClustAll/inst/doc/Vignette_Clustall.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ClustAll")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTALL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clustall"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clustall:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clustall:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clustall_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clustall_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clustall_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ClustAll)
    library(jsonlite)

    # --- create ClustAllObject [] ---
    # Key functions: createClustAll

    # --- run ClustAll [] ---
    # Key functions: runClustAll
    obj_noNA1 <- runClustAll(Object = obj_noNA, threads = 2, simplify = FALSE)
    # --- plot J A C C A R D [] ---
    # Key functions: plotJACCARD
    plotJACCARD(Object = obj_noNA1, stratification_similarity = 0.9, paint = TRUE)
    # --- explore representative clusters [] ---
    # Key functions: resStratification

    # --- plot S A N K E Y [] ---
    # Key functions: plotSANKEY

    # --- export stratifications [] ---
    # Key functions: cluster2data
    df <- cluster2data(Object = obj_noNA1,
    stratificationName = c("cuts_c_9","cuts_a_28","cuts_c_4"))
    head(df,3)
    # --- validate stratifications [] ---
    # Key functions: validateStratification
    validateStratification(obj_noNA1, "cuts_a_28")
    validateStratification(obj_noNA1, "cuts_c_9")
    validateStratification(obj_noNA1, "cuts_c_4")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clustall_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clustall_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clustall_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTALL:", paste0("    clustall: ", packageVersion("ClustAll"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustall_results.csv
    touch ${prefix}_clustall_output.rds
    echo "BIOC_CLUSTALL:" > versions.yml
    echo "    clustall: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTALL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTALL(ch_input)

    emit:
    results  = BIOC_CLUSTALL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTALL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTALL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTALL.out.versions  // channel: path(versions.yml)
}
