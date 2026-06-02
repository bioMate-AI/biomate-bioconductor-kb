#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MLSeq
// This package applies several machine learning methods, including SVM, bagSVM, Random Forest and CART
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MLSeq/inst/doc/MLSeq.R
// Upstream  : DESeq2, VennDiagram, caret, edgeR, knitr
// Downstream: none
//
// Install: BiocManager::install("MLSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MLSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mlseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mlseq:2.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mlseq:2.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mlseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mlseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mlseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(jsonlite)

    # --- define class labels [] ---
    # Key functions: DataFrame
    class <- DataFrame(condition = factor(rep(c("N","T"), c(29, 29))))
    # --- data splitting [] ---
    # Key functions: sample, DataFrame
    library(DESeq2)
    set.seed(2128)
    vars <- sort(apply(cervical, 1, var, na.rm = TRUE), decreasing = TRUE)
    # --- mwe limitations on continuous classifiers [] ---
    # Key functions: classify, show
    fit <- classify(data = data.trainS4, method = "svmRadial",
    control = trainControl(method = "repeatedcv", number = 2,
    show(fit)
    # --- Optimizing model parameters example [] ---
    # Key functions: show
    set.seed(2128)
    fit.svm <- classify(data = data.trainS4, method = "svmRadial",
    control = trainControl(method = "repeatedcv", number = 5,
    # --- fitted model svm figure [] ---
    # Key functions: cairo_pdf
    cairo_pdf(filename = "fitted_model_svm_figure.pdf", height = 5.5)
    plot(fit.svm)
    dev.off()
    # --- Get reference alleles from VCF [] ---
    # Key functions: discreteControl, classify, show, method, ref
    venn.plot <- venn.diagram(
    x = list(voomNSC = genes.vnsc, NSC = genes.pam, PLDA = genes.plda, PLDA2 = genes.plda2),
    fill = c("khaki1", "skyblue", "tomato3", "darkolivegreen3"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mlseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mlseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mlseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MLSEQ:", paste0("    mlseq: ", packageVersion("MLSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mlseq_results.csv
    touch ${prefix}_mlseq_output.rds
    echo "BIOC_MLSEQ:" > versions.yml
    echo "    mlseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MLSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MLSEQ(ch_input)

    emit:
    results  = BIOC_MLSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MLSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MLSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MLSEQ.out.versions  // channel: path(versions.yml)
}
