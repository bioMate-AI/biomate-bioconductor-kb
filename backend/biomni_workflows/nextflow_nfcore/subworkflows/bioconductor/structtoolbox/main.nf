#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: structToolbox
// An extensive set of data (pre-)processing and analysis methods and tools for metabolomics and other 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/structToolbox/inst/doc/data_analysis_omics_using_the_structtoolbox.R
// Upstream  : BiocFileCache, cowplot, ggplot2, gridExtra, openxlsx
// Downstream: none
//
// Install: BiocManager::install("structToolbox")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRUCTTOOLBOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-structtoolbox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-structtoolbox:1.18.2--r44_0' :
        'quay.io/biocontainers/bioconductor-structtoolbox:1.18.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_structtoolbox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_structtoolbox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_structtoolbox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MTBLS)
    library(MTBLS79_DatasetExperiment)
    library(PCA)
    library(PLSDA)
    library(jsonlite)

    # --- Quality control and filtering [] ---
    # Key functions: filter_na_count, filter_by_name, rowSums, model_apply, predicted
    ---------------------------------------------------------------------
    # build model sequence
    M2 = filter_na_count(
      threshold=2,
      factor_name='condition',
    # --- Dataset analysis [] ---
    # Key functions: dataset, iris_DatasetExperiment, MTBLS, MTBLS79_DatasetExperiment, pqn_norm, knn_impute, glog_transform, filter_smeta
    ---------------------------------------------------------------------
    # model sequence
    MS = permutation_test(number_of_permutations = 20,factor_name = 'Class_num') *
         kfold_xval(folds = 5,factor_name = 'Class_num') *
         (mean_centre(mode='sample_meta') + PLSR(factor_name='Class_num', number_components = 2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_structtoolbox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_structtoolbox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_structtoolbox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRUCTTOOLBOX:", paste0("    structtoolbox: ", packageVersion("structToolbox"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_structtoolbox_results.csv
    touch ${prefix}_structtoolbox_output.rds
    echo "BIOC_STRUCTTOOLBOX:" > versions.yml
    echo "    structtoolbox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRUCTTOOLBOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRUCTTOOLBOX(ch_input)

    emit:
    results  = BIOC_STRUCTTOOLBOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRUCTTOOLBOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRUCTTOOLBOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRUCTTOOLBOX.out.versions  // channel: path(versions.yml)
}
