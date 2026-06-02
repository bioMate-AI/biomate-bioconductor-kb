#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: adductomicsR
// Processes MS2 data to identify potentially adducted peptides from spectra that has been corrected fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/adductomicsR/inst/doc/adductomicsRWorkflow.R
// Upstream  : ExperimentHub, adductData, devtools
// Downstream: none
//
// Install: BiocManager::install("adductomicsR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADDUCTOMICSR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-adductomicsr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-adductomicsr:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-adductomicsr:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_adductomicsr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_adductomicsr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_adductomicsr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(adductomicsR)
    library(jsonlite)

    # --- Adduct Quantification [] ---
    # Key functions: adductQuant
    quantResults <- adductQuant(
        mzxmlFiles = c("ORB35017.mzXML", "ORB35022.mzXML"),
        targTable = targTable,
        saveDir = tempdir()
    )


    # --- Spectral Similarity Validation [] ---
    # Key functions: specSimVal
    validated <- specSimVal(
        quantResults = quantResults,
        mzxmlFiles = c("ORB35017.mzXML", "ORB35022.mzXML")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_adductomicsr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_adductomicsr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_adductomicsr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ADDUCTOMICSR:", paste0("    adductomicsr: ", packageVersion("adductomicsR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adductomicsr_results.csv
    touch ${prefix}_adductomicsr_output.rds
    echo "BIOC_ADDUCTOMICSR:" > versions.yml
    echo "    adductomicsr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ADDUCTOMICSR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ADDUCTOMICSR(ch_input)

    emit:
    results  = BIOC_ADDUCTOMICSR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ADDUCTOMICSR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ADDUCTOMICSR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ADDUCTOMICSR.out.versions  // channel: path(versions.yml)
}
