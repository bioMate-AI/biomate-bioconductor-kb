#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dada2
// The dada2 package infers exact amplicon sequence variants (ASVs) from high-throughput amplicon seque
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dada2/inst/doc/dada2-intro.R
// Upstream  : none
// Downstream: MiscMetabar
//
// Install: BiocManager::install("dada2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DADA2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dada2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dada2:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dada2:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dada2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dada2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dada2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dada2)
    library(jsonlite)

    # --- Filtering and Trimming [] ---
    # Key functions: filterAndTrim
    fnF1 <- system.file("extdata", "sam1F.fastq.gz", package="dada2")
    fnR1 <- system.file("extdata", "sam1R.fastq.gz", package="dada2")
    filtF1 <- tempfile(fileext=".fastq.gz")
    filtR1 <- tempfile(fileext=".fastq.gz")
    filterAndTrim(
        fwd=fnF1, filt=filtF1, rev=fnR1, filt.rev=filtR1,
        trimLeft=10, truncLen=c(240, 200),
        maxN=0, maxEE=2, compress=TRUE, verbose=TRUE
    )


    # --- Error Rate Learning [] ---
    # Key functions: derepFastq, learnErrors
    fnF1 <- system.file("extdata", "sam1F.fastq.gz", package="dada2")
    derepF1 <- derepFastq(fnF1, verbose=TRUE)
    errF <- learnErrors(derepF1, multithread=FALSE)


    # --- Sample Inference and Merging [] ---
    # Key functions: derepFastq, dada, mergePairs
    fnF1 <- system.file("extdata", "sam1F.fastq.gz", package="dada2")
    fnR1 <- system.file("extdata", "sam1R.fastq.gz", package="dada2")
    derepF1 <- derepFastq(fnF1, verbose=TRUE)
    derepR1 <- derepFastq(fnR1, verbose=TRUE)
    errF <- learnErrors(derepF1, multithread=FALSE)
    errR <- learnErrors(derepR1, multithread=FALSE)
    dadaF1 <- dada(derepF1, err=errF, multithread=FALSE)
    dadaR1 <- dada(derepR1, err=errR, multithread=FALSE)
    merger1 <- mergePairs(
        dadaF1, derepF1, dadaR1, derepR1, verbose=TRUE
    )


    # --- Sequence Table Construction and Chimera Removal [] ---
    # Key functions: makeSequenceTable, removeBimeraDenovo
    mock_merger <- data.frame(
        sequence = c("ACTG", "TGCA"),
        abundance = c(10, 20),
        forward = c(1, 2),
        reverse = c(1, 2)
    )
    seqtab <- makeSequenceTable(list(mock_merger))
    seqtab.nochim <- removeBimeraDenovo(
        seqtab, multithread=FALSE, verbose=TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dada2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dada2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dada2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DADA2:", paste0("    dada2: ", packageVersion("dada2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dada2_results.csv
    touch ${prefix}_dada2_output.rds
    echo "BIOC_DADA2:" > versions.yml
    echo "    dada2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DADA2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DADA2(ch_input)

    emit:
    results  = BIOC_DADA2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DADA2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DADA2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DADA2.out.versions  // channel: path(versions.yml)
}
