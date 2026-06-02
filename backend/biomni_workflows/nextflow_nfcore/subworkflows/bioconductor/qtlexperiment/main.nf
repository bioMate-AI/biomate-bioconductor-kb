#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QTLExperiment
// QLTExperiment defines an S4 class for storing and manipulating summary statistics from QTL mapping e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QTLExperiment/inst/doc/QTLExperiment.R
// Upstream  : none
// Downstream: multistateQTL
//
// Install: BiocManager::install("QTLExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QTLEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qtlexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qtlexperiment:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qtlexperiment:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qtlexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qtlexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qtlexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QTLExperiment)
    library(jsonlite)


    # --- Mock Summary Statistics [] ---
    # Key functions: mockSummaryStats, QTLExperiment, sample, gene_, state_
    set.seed(42)
    nStates <- 6
    nQTL <- 40

    mock_summary_stats <- mockSummaryStats(nStates=nStates, nQTL=nQTL)
    mock_summary_stats$betas[1:5,1:5]
    qtle <- QTLExperiment(
        assays=list(
            betas=mock_summary_stats$betas,
            errors=mock_summary_stats$errors),
        metadata=list(study="mock-example"))
    qtle
    mock_summary_stats <- mockSummaryStats(nStates=nStates, nQTL=nQTL, names=FALSE)
    mock_summary_stats$betas[1:5,1:5]
    qtle <- QTLExperiment(assays=list(betas=mock_summary_stats$betas,
                                      errors=mock_summary_stats$errors),
                          feature_id=paste0("gene_", 1:nQTL),
                          variant_id=sample(1:1e6, nQTL),
                          state_id=paste0("state_", LETTERS[1:nStates]),
                          metadata=list(study="mock-example2"))

    # --- Create Mock Qtle Wrapper [] ---
    # Key functions: mockQTLE, sumstats2qtle, betas, extdata, lung, thyroid, spleen, blood
    qtle <- mockQTLE(nStates=nStates, nQTL=nQTL)
    qtle
    input_path <- system.file("extdata", package="QTLExperiment")
    state <- c("lung", "thyroid", "spleen", "blood")

    input <- data.frame(
        state=state, 
        path=paste0(input_path, "/GTEx_tx_", state, ".tsv"))

    # --- Show Dim [] ---
    # Key functions: rowData
    dim(qtle4)
    colnames(qtle4)
    head(rowData(qtle4))

    # --- Show Bind Functions [] ---
    # Key functions: state_id, feature_id, rowData, geneA, state1, state2
    qtle4b <- qtle4
    state_id(qtle4b) <- paste0(state_id(qtle4), "_b")
    dim(cbind(qtle4, qtle4b))
    qtle4b <- qtle4
    feature_id(qtle4b) <- paste0(feature_id(qtle4), "_b")
    dim(rbind(qtle4, qtle4b))
    qtle.subset <- qtle[rowData(qtle)$feature_id == "geneA", ]
    dim(qtle.subset)

    qtle.subset <- qtle[, c("state1", "state2")]
    dim(qtle.subset)

    qtle.subset <- subset(qtle, , sample_size > 100)
    dim(qtle.subset)

    # --- Convenient Getters Setters [] ---
    # Key functions: betas, assay, significant, pvalues, state_id, feature_id, variant_id
    betas(qtle)[1:5,1:5]

    betas(qtle) <- betas(qtle) * -1

    betas(qtle)[1:5,1:5]
    assay(qtle4, "significant") <- assay(qtle4, "pvalues") < 0.05

    assay(qtle4, "significant")[1:5, 1:4]
    state_id(qtle4)
    feature_id(qtle4)[1:3]
    variant_id(qtle4)[1:3]

    # --- Special Setters [] ---
    # Key functions: state_id, colData, betas, DataFrame, recover_qtle_ids, rowData, sample
    state_id(qtle4) <- c("LUNG", "THYROID", "SPLEEN", "BLOOD")
    head(colData(qtle4))
    head(betas(qtle4))
    new_colData <- DataFrame(list(some_info1=LETTERS[1:ncol(qtle4)],
                                  some_info2=c(1:ncol(qtle4))))
    colData(qtle4) <- new_colData
    head(colData(qtle4))

    qtle4 <- recover_qtle_ids(qtle4)
    head(colData(qtle4))
    rowData(qtle4)$variant_id <- sample(rowData(qtle4)$variant_id, nrow(qtle4))

    head(rowData(qtle4))


    qtle4 <- recover_qtle_ids(qtle4)
    head(rowData(qtle4))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qtlexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qtlexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qtlexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QTLEXPERIMENT:", paste0("    qtlexperiment: ", packageVersion("QTLExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qtlexperiment_results.csv
    touch ${prefix}_qtlexperiment_output.rds
    echo "BIOC_QTLEXPERIMENT:" > versions.yml
    echo "    qtlexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QTLEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QTLEXPERIMENT(ch_input)

    emit:
    results  = BIOC_QTLEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QTLEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QTLEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QTLEXPERIMENT.out.versions  // channel: path(versions.yml)
}
