#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sampleClassifier
// The package is designed to classify microarray RNA-seq gene expression profiles.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sampleClassifier/inst/doc/sampleClassifier.R
// Upstream  : sampleClassifierData
// Downstream: none
//
// Install: BiocManager::install("sampleClassifier")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SAMPLECLASSIFIER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sampleclassifier"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sampleclassifier:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sampleclassifier:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sampleclassifier_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sampleclassifier_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sampleclassifier_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sampleClassifier)
    library(jsonlite)

    # --- Microarray SVM Classification [] ---
    # Key functions: classifyProfile.svm
    res1.svm.df <- classifyProfile.svm(
        ref_matrix = micro_refmat,
        query_mat = micro_testmat,
        chip1 = "hgu133plus2",
        chip2 = "hgu133a"
    )


    # --- RNA-seq Profile Classification [] ---
    # Key functions: classifyProfile.rnaseq
    res2.list <- classifyProfile.rnaseq(
        ref_matrix = rnaseq_refmat,
        query_mat = rnaseq_testmat,
        gene.ids.type = "ensembl",
        write2File = FALSE
    )


    # --- RNA-seq SVM Classification [] ---
    # Key functions: classifyProfile.rnaseq.svm
    res2.svm.df <- classifyProfile.rnaseq.svm(
        ref_matrix = rnaseq_refmat,
        query_mat = rnaseq_testmat,
        gene.ids.type = "ensembl"
    )


    # --- Visualization of Classification Results [] ---
    # Key functions: get.heatmap
    get.heatmap(res1.list)
    get.heatmap(res2.list)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sampleclassifier_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sampleclassifier_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sampleclassifier_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SAMPLECLASSIFIER:", paste0("    sampleclassifier: ", packageVersion("sampleClassifier"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sampleclassifier_results.csv
    touch ${prefix}_sampleclassifier_output.rds
    echo "BIOC_SAMPLECLASSIFIER:" > versions.yml
    echo "    sampleclassifier: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SAMPLECLASSIFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SAMPLECLASSIFIER(ch_input)

    emit:
    results  = BIOC_SAMPLECLASSIFIER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SAMPLECLASSIFIER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SAMPLECLASSIFIER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SAMPLECLASSIFIER.out.versions  // channel: path(versions.yml)
}
