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

    # --- chu 2 [] ---
    # Key functions: assay, colData
    data(SE)
    assay(SE)[1:5, c(1:5, 21:25)]
    colData(SE)
    # --- chu 5 [] ---
    # Key functions: assay

    # --- chu 10 [] ---
    # Key functions: assay
    data_adjust<-DaMiR.SVadjust(data_filt, sv, n.sv=4)
    assay(data_adjust[c(1:5), c(1:5, 21:25)])
    # --- chu 13 [] ---
    # Key functions: colData
    set.seed(12345)
    data_clean<-DaMiR.transpose(assay(data_adjust))
    df<-colData(data_adjust)
    # --- chu 17bis1 [] ---
    # Key functions: sample
    set.seed(10101)
    idx_test <- sample(1:ncol(data_adjust), 10)
    idx_test_cl1<-sample(1:(ncol(data_adjust)/2), nSampl_cl1)
    # --- chu 17bis12 [] ---
    # Key functions: rep
    cv_sample <- c(rep(seq_len(nfold), each=ncol(Learning_set)/(2*nfold)),
    rep(seq_len(nfold), each=ncol(Learning_set)/(2*nfold)))
    cv_models <- list()
    # --- chu 18 [] ---
    # Key functions: colData
    set.seed(12345)
    data_clean_2<-DaMiR.transpose(assay(data_filt))
    df_2<-colData(data_filt)
    # --- to Latex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

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
