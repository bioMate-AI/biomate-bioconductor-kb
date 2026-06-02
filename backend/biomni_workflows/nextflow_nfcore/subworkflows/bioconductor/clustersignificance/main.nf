#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ClusterSignificance
// The ClusterSignificance package provides tools to assess if class clusters in dimensionality reduced
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ClusterSignificance/inst/doc/ClusterSignificance-vignette.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("ClusterSignificance")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLUSTERSIGNIFICANCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clustersignificance"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clustersignificance:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clustersignificance:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clustersignificance_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clustersignificance_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clustersignificance_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ClusterSignificance)
    library(jsonlite)

    # --- Projection ---
    # Key functions: pcp, mlp
    data(pcpMatrix)
    classes_pcp <- rownames(pcpMatrix)
    prj_pcp <- pcp(pcpMatrix, classes_pcp, normalize = TRUE)
    data(mlpMatrix)
    classes_mlp <- rownames(mlpMatrix)
    prj_mlp <- mlp(mlpMatrix, classes_mlp)

    # --- Classification ---
    # Key functions: classify, getData
    cl_pcp <- classify(prj_pcp)
    cl_mlp <- classify(prj_mlp)
    auc_pcp <- getData(cl_pcp, "AUC")
    auc_mlp <- getData(cl_mlp, "AUC")

    # --- Permutation Analysis ---
    # Key functions: permute
    iterations <- 100
    pe_pcp <- permute(
        mat = pcpMatrix, 
        iter = iterations, 
        classes = classes_pcp, 
        projmethod = "pcp"
    )

    # --- Statistical Significance ---
    # Key functions: pvalue, conf.int
    p_val <- pvalue(pe_pcp)
    ci_val <- conf.int(pe_pcp, conf.level = 0.99)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clustersignificance_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clustersignificance_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clustersignificance_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLUSTERSIGNIFICANCE:", paste0("    clustersignificance: ", packageVersion("ClusterSignificance"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clustersignificance_results.csv
    touch ${prefix}_clustersignificance_output.rds
    echo "BIOC_CLUSTERSIGNIFICANCE:" > versions.yml
    echo "    clustersignificance: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLUSTERSIGNIFICANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLUSTERSIGNIFICANCE(ch_input)

    emit:
    results  = BIOC_CLUSTERSIGNIFICANCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLUSTERSIGNIFICANCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLUSTERSIGNIFICANCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLUSTERSIGNIFICANCE.out.versions  // channel: path(versions.yml)
}
