#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: phenomis
// The 'phenomis' package provides methods to perform post-processing (i.e. quality control and normali
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/phenomis/inst/doc/phenomis-vignette.R
// Upstream  : MultiAssayExperiment, MultiDataSet, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("phenomis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHENOMIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phenomis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phenomis:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phenomis:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phenomis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phenomis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phenomis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExpressionSet)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Create SummarizedExperiment [] ---
    # Key functions: SummarizedExperiment, listToMap
    library(MultiAssayExperiment)
    experiment.ls <- list()
    sampleMap.ls <- list()
    # --- Assay data access [] ---
    # Key functions: assay, colData, inspecting, annotating_parameters, kable, writing, sampleNames, pData
    sacurine.se <- annotating(sacurine.se,
    param.ls = list(query.type = "mz",
    knitr::kable(rowData(sacurine.se)[!is.na(rowData(sacurine.se)[, "localMS.accession"]), grep("localMS.", colnames(rowData(sacurine.se)), fixed = TRUE)])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phenomis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phenomis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phenomis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHENOMIS:", paste0("    phenomis: ", packageVersion("phenomis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phenomis_results.csv
    touch ${prefix}_phenomis_output.rds
    echo "BIOC_PHENOMIS:" > versions.yml
    echo "    phenomis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHENOMIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHENOMIS(ch_input)

    emit:
    results  = BIOC_PHENOMIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHENOMIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHENOMIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHENOMIS.out.versions  // channel: path(versions.yml)
}
