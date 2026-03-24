#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rRDP
// This package installs and interfaces the naive Bayesian classifier for 16S rRNA sequences developed 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rRDP/inst/doc/rRDP.R
// Upstream  : none
// Downstream: rRDPData
//
// Install: BiocManager::install("rRDP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RRDP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rrdp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rrdp:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rrdp:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rrdp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rrdp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rrdp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rRDP)
    library(jsonlite)

    # --- Readrnastringset [] ---
    # Key functions: readRNAStringSet
    ---------------------------------------------------------------------
    seq <- readRNAStringSet(system.file("examples/RNA_example.fasta",
        package = "rRDP"
    ))
    seq
    # --- Predict [] ---
    # Key functions: predict, rdp
    ---------------------------------------------------------------------
    pred <- predict(rdp(), seq)
    pred
    # --- Attr [] ---
    # Key functions: attr
    ---------------------------------------------------------------------
    attr(pred, "confidence")
    # --- Decode Greengenes [] ---
    # Key functions: decode_Greengenes
    ---------------------------------------------------------------------
    actual <- decode_Greengenes(annotation)
    actual
    # --- Confusiontable [] ---
    # Key functions: confusionTable, accuracy
    ---------------------------------------------------------------------
    confusionTable(actual, pred, rank = "genus")
    accuracy(actual, pred, rank = "genus")
    # --- Readdnastringset [] ---
    # Key functions: readDNAStringSet
    ---------------------------------------------------------------------
    trainingSequences <- readDNAStringSet(
        system.file("examples/trainingSequences.fasta", package = "rRDP")
    )
    trainingSequences
    # --- Trainrdp [] ---
    # Key functions: trainRDP
    ---------------------------------------------------------------------
    customRDP <- trainRDP(trainingSequences, dir = "myRDP")
    customRDP
    # --- Readdnastringset [] ---
    # Key functions: readDNAStringSet, predict
    ---------------------------------------------------------------------
    testSequences <- readDNAStringSet(
        system.file("examples/testSequences.fasta", package = "rRDP")
    )
    pred <- predict(customRDP, testSequences)
    # --- Rdp [] ---
    # Key functions: rdp
    ---------------------------------------------------------------------
    customRDP <- rdp(dir = "myRDP")
    # --- Removerdp [] ---
    # Key functions: removeRDP
    ---------------------------------------------------------------------
    removeRDP(customRDP)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rrdp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rrdp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rrdp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RRDP:", paste0("    rrdp: ", packageVersion("rRDP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rrdp_results.csv
    touch ${prefix}_rrdp_output.rds
    echo "BIOC_RRDP:" > versions.yml
    echo "    rrdp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RRDP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RRDP(ch_input)

    emit:
    results  = BIOC_RRDP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RRDP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RRDP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RRDP.out.versions  // channel: path(versions.yml)
}
