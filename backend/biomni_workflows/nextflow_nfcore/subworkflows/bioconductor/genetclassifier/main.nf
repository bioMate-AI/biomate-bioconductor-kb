#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: geNetClassifier
// Comprehensive package to automatically train and validate a multi-class SVM classifier based on gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/geNetClassifier/inst/doc/geNetClassifier-vignette.R
// Upstream  : leukemiasEset
// Downstream: none
//
// Install: BiocManager::install("geNetClassifier")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENETCLASSIFIER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genetclassifier"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genetclassifier:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genetclassifier:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genetclassifier_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genetclassifier_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genetclassifier_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(geNetClassifier)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: data
    library(leukemiasEset)
    data(leukemiasEset)
    leukemiasEset
    # --- Quality control and filtering [] ---
    # Key functions: pData
    ## pData(leukemiasEset)
    # --- RequireNamespace analysis [] ---
    # Key functions: requireNamespace, packages, featureNames, objects, geNetClassifier, numGenes, getTopRanking, getRanking
    ## plotExpressionProfiles(leukemiasEset, genes=topGenes[,3, drop=FALSE],
    ##                        sampleLabels="LeukemiaType",
    ##                        showMean=TRUE, identify=FALSE,
    ##                        sampleColors=c("grey","red")
    ##                        [(sampleNames(leukemiasEset)%in% c("GSM331386.CEL","GSM331392.CEL"))+1])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genetclassifier_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genetclassifier_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genetclassifier_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENETCLASSIFIER:", paste0("    genetclassifier: ", packageVersion("geNetClassifier"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genetclassifier_results.csv
    touch ${prefix}_genetclassifier_output.rds
    echo "BIOC_GENETCLASSIFIER:" > versions.yml
    echo "    genetclassifier: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENETCLASSIFIER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENETCLASSIFIER(ch_input)

    emit:
    results  = BIOC_GENETCLASSIFIER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENETCLASSIFIER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENETCLASSIFIER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENETCLASSIFIER.out.versions  // channel: path(versions.yml)
}
