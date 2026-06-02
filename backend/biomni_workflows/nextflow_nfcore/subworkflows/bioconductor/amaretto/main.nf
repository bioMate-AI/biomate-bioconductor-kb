#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AMARETTO
// Integrating an increasing number of available multi-omics cancer data remains one of the main challe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AMARETTO/inst/doc/amaretto.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("AMARETTO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AMARETTO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-amaretto"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-amaretto:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-amaretto:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_amaretto_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_amaretto_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_amaretto_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AMARETTO)
    library(AMARETTO_Download)
    library(AMARETTO_EvaluateTestSet)
    library(AMARETTO_HTMLreport)
    library(AMARETTO_Initialize)
    library(AMARETTO_Preprocess)
    library(AMARETTO_Run)
    library(AMARETTO_VisualizeModule)
    library(jsonlite)

    # --- Run AMARETTO Algorithm [] ---
    # Key functions: AMARETTO_Run
    AMARETTOresults <- AMARETTO_Run(
        AMARETTOinit = AMARETTOinit
    )


    # --- Evaluate Test Set [] ---
    # Key functions: AMARETTO_EvaluateTestSet
    AMARETTOtestReport <- AMARETTO_EvaluateTestSet(
        AMARETTOresults = AMARETTOresults,
        MA_Data_TestSet = AMARETTOinit$MA_matrix_Var,
        RegulatorData_TestSet = AMARETTOinit$RegulatorData
    )


    # --- Visualize Module [] ---
    # Key functions: AMARETTO_VisualizeModule
    AMARETTO_VisualizeModule(
        AMARETTOinit = AMARETTOinit,
        AMARETTOresults = AMARETTOresults,
        ProcessedData = ProcessedDataLIHC,
        ModuleNr = 1
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_amaretto_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_amaretto_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_amaretto_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AMARETTO:", paste0("    amaretto: ", packageVersion("AMARETTO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_amaretto_results.csv
    touch ${prefix}_amaretto_output.rds
    echo "BIOC_AMARETTO:" > versions.yml
    echo "    amaretto: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AMARETTO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AMARETTO(ch_input)

    emit:
    results  = BIOC_AMARETTO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AMARETTO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AMARETTO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AMARETTO.out.versions  // channel: path(versions.yml)
}
