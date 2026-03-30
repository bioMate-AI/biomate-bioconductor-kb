#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: knowYourCG
// knowYourCG automates the functional analysis of DNA methylation data. The package tests the enrichme
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/knowYourCG/inst/doc/Array.R
// Upstream  : sesameData, SummarizedExperiment, gprofiler2, knitr, sesame
// Downstream: none
//
// Install: BiocManager::install("knowYourCG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-knowyourcg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-knowyourcg:1.2.5--r44_0' :
        'quay.io/biocontainers/bioconductor-knowyourcg:1.2.5--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_knowyourcg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_knowyourcg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_knowyourcg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(knowYourCG)
    library(jsonlite)

    # --- Feature metadata inspection [] ---
    # Key functions: sesameDataCache, getDBs, testEnrichment, listDBGroups, rowData, buildGeneDBs, testGO, testProbeProximity
    query <- names(sesameData_getProbesByGene("Dnmt3a", "MM285"))
    dbs <- c("KYCG.MM285.chromHMM.20210210","KYCG.HM450.TFBSconsensus.20211013",
    results <- testEnrichment(query,databases=dbs,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_knowyourcg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_knowyourcg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_knowyourcg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KNOWYOURCG:", paste0("    knowyourcg: ", packageVersion("knowYourCG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_knowyourcg_results.csv
    touch ${prefix}_knowyourcg_output.rds
    echo "BIOC_KNOWYOURCG:" > versions.yml
    echo "    knowyourcg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KNOWYOURCG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KNOWYOURCG(ch_input)

    emit:
    results  = BIOC_KNOWYOURCG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KNOWYOURCG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KNOWYOURCG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KNOWYOURCG.out.versions  // channel: path(versions.yml)
}
