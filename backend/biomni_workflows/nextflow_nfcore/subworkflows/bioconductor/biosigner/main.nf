#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biosigner
// Feature selection is critical in omics data analysis to extract restricted and meaningful molecular 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biosigner/inst/doc/biosigner-vignette.R
// Upstream  : BioMark, Biobase, MultiAssayExperiment, SummarizedExperiment, golubEsets
// Downstream: none
//
// Install: BiocManager::install("biosigner")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOSIGNER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biosigner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biosigner:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biosigner:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biosigner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biosigner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biosigner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biosigner)
    library(jsonlite)

    # --- Signature Extraction and Visualization [] ---
    # Key functions: getSignatureLs, plot
    sig_features <- getSignatureLs(diaSign)[["complete"]]
    plot(diaSign, typeC = "boxplot")
    plot(diaSign, typeC = "tier")


    # --- Prediction and Performance Evaluation [] ---
    # Key functions: predict, getAccuracyMN
    predictions <- predict(diaSign)
    accuracy <- getAccuracyMN(diaSign)


    # --- Multi-Assay and SummarizedExperiment Integration [] ---
    # Key functions: biosign, getBiosign
    data(diaplasma)
    dia.se <- SummarizedExperiment::SummarizedExperiment(
        assays = list(diaplasma = t(diaplasma$dataMatrix[1:20, 1:50])),
        colData = diaplasma$sampleMetadata[1:20, ]
    )
    dia.se <- biosign(dia.se, "type", bootI = 5)
    dia_models <- getBiosign(dia.se)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biosigner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biosigner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biosigner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOSIGNER:", paste0("    biosigner: ", packageVersion("biosigner"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biosigner_results.csv
    touch ${prefix}_biosigner_output.rds
    echo "BIOC_BIOSIGNER:" > versions.yml
    echo "    biosigner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOSIGNER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOSIGNER(ch_input)

    emit:
    results  = BIOC_BIOSIGNER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOSIGNER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOSIGNER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOSIGNER.out.versions  // channel: path(versions.yml)
}
