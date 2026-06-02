#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DaMiRseq
// The DaMiRseq package offers a tidy pipeline of data mining procedures to identify transcriptional bi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DaMiRseq/inst/doc/DaMiRseq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DaMiRseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DAMIRSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-damirseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-damirseq:2.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-damirseq:2.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_damirseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_damirseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_damirseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DaMiRseq)
    library(jsonlite)

    # --- Batch Effect Correction [] ---
    # Key functions: DaMiR.SV, DaMiR.SVadjust, DaMiR.Allplot
    sv <- DaMiR.SV(data_filt)
    data_adjust <- DaMiR.SVadjust(data_filt, sv, n.sv = 4)
    DaMiR.Allplot(data_adjust, colData(data_adjust))


    # --- Feature Selection and Dimension Reduction [] ---
    # Key functions: DaMiR.transpose, DaMiR.FSelect, DaMiR.FReduct, DaMiR.MDSplot
    data_clean <- DaMiR.transpose(assay(data_adjust))
    df <- colData(data_adjust)
    data_reduced <- DaMiR.FSelect(data_clean, df, th.corr = 0.4)
    data_reduced_red <- DaMiR.FReduct(data_reduced$data)
    DaMiR.MDSplot(data_reduced_red, df)


    # --- Feature Ranking and Selection [] ---
    # Key functions: DaMiR.FSort, DaMiR.FBest, DaMiR.Clustplot
    df_importance <- DaMiR.FSort(data_reduced_red, df)
    selected_features <- DaMiR.FBest(
        data_reduced_red,
        ranking = df_importance,
        n.pred = 5
    )
    DaMiR.Clustplot(selected_features$data, df)


    # --- Ensemble Learning Classification [] ---
    # Key functions: DaMiR.EnsembleLearning
    classification_res <- DaMiR.EnsembleLearning(
        selected_features$data,
        classes = df$class,
        fSample.tr = 0.5,
        fSample.tr.w = 0.5,
        iter = 10
    )


    # --- Model Training and Prediction [] ---
    # Key functions: DaMiR.EnsL_Train, DaMiR.EnsL_Predict
    idx_test <- c(1:5, 21:25)
    test_set <- data_adjust[, idx_test, drop = FALSE]
    train_set <- data_adjust[, -idx_test, drop = FALSE]
    train_features <- train_set[selected_features$predictors, , drop = FALSE]
    test_features <- test_set[selected_features$predictors, , drop = FALSE]
    ensl_model <- DaMiR.EnsL_Train(train_features, cl_type = c("RF", "LR"))
    res_predict <- DaMiR.EnsL_Predict(test_features, bestModel = ensl_model)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_damirseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_damirseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_damirseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DAMIRSEQ:", paste0("    damirseq: ", packageVersion("DaMiRseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_damirseq_results.csv
    touch ${prefix}_damirseq_output.rds
    echo "BIOC_DAMIRSEQ:" > versions.yml
    echo "    damirseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DAMIRSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DAMIRSEQ(ch_input)

    emit:
    results  = BIOC_DAMIRSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DAMIRSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DAMIRSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DAMIRSEQ.out.versions  // channel: path(versions.yml)
}
