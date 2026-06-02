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
    library(DatasetExperiment)
    library(PCA)
    library(jsonlite)

    # --- Struct Class [] ---
    # Key functions: struct_class
    ---------------------------------------------------------------------
    S = struct_class()
    S
    # --- Datasetexperiment [] ---
    # Key functions: DatasetExperiment, frame
    ---------------------------------------------------------------------
    DE = DatasetExperiment(
      data = iris[,1:4],
      sample_meta=iris[,5,drop=FALSE],
      variable_meta=data.frame('idx'=1:4,row.names=colnames(data)),
    # --- Iris Datasetexperiment [] ---
    # Key functions: iris_DatasetExperiment
    ---------------------------------------------------------------------
    DE = iris_DatasetExperiment()
    DE
    # --- Set Struct Obj [] ---
    # Key functions: set_struct_obj
    ---------------------------------------------------------------------
    # mean centre object
    mean_centre = set_struct_obj(
      class_name = 'mean_centre',
      struct_obj = 'model',
    # --- Mean Centre [] ---
    # Key functions: mean_centre, PCA
    ---------------------------------------------------------------------
    M = mean_centre()
    M
    P = PCA(number_components=4)
    P
    # --- Set Obj Method [] ---
    # Key functions: set_obj_method, colMeans, int
    ---------------------------------------------------------------------
    # mean centre training
    set_obj_method(
      class_name = 'mean_centre',
      method_name = 'model_train',
    # --- Mean Centre [] ---
    # Key functions: mean_centre, model_train, iris_DatasetExperiment, model_predict, colMeans
    ---------------------------------------------------------------------
    # create instance of object
    M = mean_centre()
    # train with iris data
    M = model_train(M,iris_DatasetExperiment())
    # --- Set Obj Method [] ---
    # Key functions: set_obj_method, svd, frame
    ---------------------------------------------------------------------
    # PCA training
    set_obj_method(
      class_name = 'PCA',
      method_name = 'model_train',
    # --- Model Apply [] ---
    # Key functions: model_apply
    ---------------------------------------------------------------------
    # get the mean centred data
    DC = M$centred
    # train PCA model
    P = model_apply(P,DC)
    # --- Mean Centre [] ---
    # Key functions: mean_centre, PCA
    ---------------------------------------------------------------------
    # create model sequence
    MS = mean_centre() + PCA(number_components = 2)
    # print summary
    MS
    # --- Model Apply [] ---
    # Key functions: model_apply, iris_DatasetExperiment, sequence, predicted
    ---------------------------------------------------------------------
    # apply model sequence to iris_data
    MS = model_apply(MS,iris_DatasetExperiment())
    # get default output from sequence (PCA scores with 2 components)
    predicted(MS)
    # --- Iterator [] ---
    # Key functions: iterator, models
    ---------------------------------------------------------------------
    # create iterator
    I = iterator()
    # add PCA model sequence
    models(I) = MS
    # --- Iterator [] ---
    # Key functions: iterator, mean_centre, PCA, models
    ---------------------------------------------------------------------
    # alternative to assign models for iterators
    I = iterator() * (mean_centre() + PCA())
    models(I)
    # --- Iterator [] ---
    # Key functions: iterator, mean_centre, PCA
    ---------------------------------------------------------------------
    I = iterator() * iterator() * (mean_centre() + PCA())
    # --- Set Struct Obj [] ---
    # Key functions: set_struct_obj
    ---------------------------------------------------------------------
    # new chart object
    set_struct_obj(
      class_name = 'pca_scores_plot',
      struct_obj = 'chart',

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
