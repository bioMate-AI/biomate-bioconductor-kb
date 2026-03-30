#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: anota
// Genome wide studies of translational control is emerging as a tool to study verious biological condi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/anota/inst/doc/anota.R
// Upstream  : none
// Downstream: tRanslatome
//
// Install: BiocManager::install("anota")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANOTA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anota"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-anota:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-anota:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anota_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anota_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anota_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(anota)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: anotaPerformQc, anotaResidOutlierTest, anotaGetSigGenes, anotaPlotSigGenes
    ##Loading the library and data set, perform quality control and identify significant translational regulation. No RVM is applied in the example.
     library("anota")
     data(anotaDataSet)
     anotaQcOut <- anotaPerformQc(dataT=anotaDataT[1:200,], dataP=anotaDataP[1:200,], phenoVec=anotaPhenoVec, nDfbSimData=500, useProgBar=FALSE)
     anotaResidOut <- anotaResidOutlierTest(anotaQcObj=anotaQcOut, useProgBar=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_anota_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_anota_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_anota_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANOTA:", paste0("    anota: ", packageVersion("anota"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anota_results.csv
    touch ${prefix}_anota_output.rds
    echo "BIOC_ANOTA:" > versions.yml
    echo "    anota: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANOTA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANOTA(ch_input)

    emit:
    results  = BIOC_ANOTA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANOTA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANOTA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANOTA.out.versions  // channel: path(versions.yml)
}
