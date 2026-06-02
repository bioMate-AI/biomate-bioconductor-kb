#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNAmodR
// RNAmodR provides classes and workflows for loading/aggregation data from high througput sequencing a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNAmodR/inst/doc/RNAmodR.R
// Upstream  : GenomicFeatures, Rsamtools, rtracklayer, txdbmaker
// Downstream: RNAmodR.AlkAnilineSeq, RNAmodR.ML, RNAmodR.RiboMethSeq
//
// Install: BiocManager::install("RNAmodR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAMODR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnamodr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnamodr:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnamodr:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnamodr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnamodr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnamodr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNAmodR)
    library(End5SequenceData)
    library(GFF3File)
    library(ModInosine)
    library(ModSetInosine)
    library(jsonlite)

    # --- Modification Detection and Settings [] ---
    # Key functions: ModInosine, ModSetInosine, settings, modifications
    mi <- ModInosine(files, annotation = annotation, sequences = sequences)
    settings(mi) <- list(minScore = 0.5)
    files_set <- list(
        "SampleSet1" = c(treated = RNAmodR.Data::RNAmodR.Data.example.wt.1())
    )
    msi <- ModSetInosine(
        files_set,
        annotation = annotation,
        sequences = sequences
    )
    mod <- modifications(msi)


    # --- Comparative Visualization and Statistics [] ---
    # Key functions: compareByCoord, plotCompareByCoord, plotData, plotROC, stats
    coord <- unique(unlist(mod))
    coord$score <- NULL
    coord$sd <- NULL
    comp <- compareByCoord(msi, coord)
    txdb <- txdbmaker::makeTxDbFromGFF(annotation)
    alias <- data.frame(
        tx_id = names(GenomicFeatures::id2name(txdb)),
        name = GenomicFeatures::id2name(txdb)
    )
    plotCompareByCoord(msi, coord, alias = alias)
    plotData(msi, "2", from = 10L, to = 45L, alias = alias)
    plotROC(msi, coord)
    msi_stats <- stats(msi)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnamodr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnamodr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnamodr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNAMODR:", paste0("    rnamodr: ", packageVersion("RNAmodR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnamodr_results.csv
    touch ${prefix}_rnamodr_output.rds
    echo "BIOC_RNAMODR:" > versions.yml
    echo "    rnamodr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNAMODR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNAMODR(ch_input)

    emit:
    results  = BIOC_RNAMODR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNAMODR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNAMODR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNAMODR.out.versions  // channel: path(versions.yml)
}
