#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: struct
// Defines and includes a set of class-based templates for developing and implementing data processing 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/struct/inst/doc/struct_templates_and_helper_functions.R
// Upstream  : ggplot2
// Downstream: MetMashR, structToolbox
//
// Install: BiocManager::install("struct")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRUCT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-struct"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-struct:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-struct:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_struct_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_struct_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_struct_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(struct)
    library(DatasetExperiment)
    library(PCA)
    library(jsonlite)

    # --- Model Definition [] ---
    # Key functions: set_struct_obj, set_obj_method
    mean_centre <- set_struct_obj(
        class_name = 'mean_centre',
        struct_obj = 'model',
        params = character(0),
        outputs = c(centred = 'DatasetExperiment', mean = 'numeric'),
        private = character(0),
        prototype = list(predicted = 'centred')
    )
    set_obj_method(
        class_name = 'mean_centre',
        method_name = 'model_train',
        definition = function(M, D) {
            M$mean <- colMeans(D$data)
            return(M)
        }
    )
    set_obj_method(
        class_name = 'mean_centre',
        method_name = 'model_predict',
        definition = function(M, D) {
            D$data <- D$data - rep(
                M$mean,
                rep.int(nrow(D$data), ncol(D$data))
            )
            M$centred <- D
            return(M)
        }
    )


    # --- Model Training and Prediction [] ---
    # Key functions: mean_centre, model_train, model_predict
    M <- mean_centre()
    M <- model_train(M, iris_DatasetExperiment())
    M <- model_predict(M, iris_DatasetExperiment())
    centred_data <- M$centred$data


    # --- Model Sequencing [] ---
    # Key functions: PCA, model_apply, predicted
    PCA <- set_struct_obj(
        class_name = 'PCA',
        struct_obj = 'model',
        params = c(number_components = 'numeric'),
        outputs = c(scores = 'DatasetExperiment', loadings = 'data.frame'),
        private = character(0),
        prototype = list(
            number_components = 2,
            ontology = 'OBI:0200051',
            predicted = 'scores'
        )
    )
    MS <- mean_centre() + PCA(number_components = 2)
    MS <- model_apply(MS, iris_DatasetExperiment())
    pca_scores <- predicted(MS)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_struct_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_struct_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_struct_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRUCT:", paste0("    struct: ", packageVersion("struct"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_struct_results.csv
    touch ${prefix}_struct_output.rds
    echo "BIOC_STRUCT:" > versions.yml
    echo "    struct: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRUCT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRUCT(ch_input)

    emit:
    results  = BIOC_STRUCT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRUCT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRUCT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRUCT.out.versions  // channel: path(versions.yml)
}
