#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HybridMTest
// Performs hybrid multiple testing that incorporates method selection and assumption evaluations into 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HybridMTest/inst/doc/HybridMTest.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HybridMTest")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HYBRIDMTEST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hybridmtest"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hybridmtest:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hybridmtest:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hybridmtest_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hybridmtest_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hybridmtest_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HybridMTest)
    library(jsonlite)

    # --- Loadcorrelationdata [] ---
    # Key functions: exprs, pData, frame, test
    library(HybridMTest)
    data(correlation.data)
    Y<-exprs(correlation.data)
    x<-pData(correlation.data)
    # --- Loadcomparisondata [] ---
    # Key functions: exprs, pData, frame
    library(HybridMTest)
    data(GroupComp.data)
    brain.express.set <- exprs(GroupComp.data)
    brain.pheno.data  <- pData(GroupComp.data)
     brain.express.set[1:5, 1:8]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hybridmtest_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hybridmtest_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hybridmtest_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HYBRIDMTEST:", paste0("    hybridmtest: ", packageVersion("HybridMTest"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hybridmtest_results.csv
    touch ${prefix}_hybridmtest_output.rds
    echo "BIOC_HYBRIDMTEST:" > versions.yml
    echo "    hybridmtest: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HYBRIDMTEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HYBRIDMTEST(ch_input)

    emit:
    results  = BIOC_HYBRIDMTEST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HYBRIDMTEST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HYBRIDMTEST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HYBRIDMTEST.out.versions  // channel: path(versions.yml)
}
