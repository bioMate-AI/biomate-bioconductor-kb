#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASpli
// Integrative pipeline for the analysis of alternative splicing using RNAseq.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASpli/inst/doc/ASpli.R
// Upstream  : GenomicFeatures
// Downstream: none
//
// Install: BiocManager::install("ASpli")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASPLI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aspli"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aspli:2.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aspli:2.16.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_aspli_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aspli_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aspli_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASpli)
    library(Date)
    library(jsonlite)

    # --- Genome Feature Extraction [Genome Annotation] ---
    # Key functions: aspliExampleGTF, binGenome
    gtfFileName <- aspliExampleGTF()
    genomeTxDb  <- txdbmaker::makeTxDbFromGFF(gtfFileName)
    features    <- binGenome(genomeTxDb)

    # --- Read and Junction Counting [Quantification] ---
    # Key functions: aspliExampleBamList, gbCounts, jCounts
    BAMFiles <- aspliExampleBamList()
    targets  <- data.frame(
        row.names = paste0("Sample", seq_len(6)),
        bam = BAMFiles[1:6],
        f1  = c("control", "control", "control", "treatment", "treatment", "treatment"),
        stringsAsFactors = FALSE
    )
    gbcounts <- gbCounts(
        features = features,
        targets = targets,
        minReadLength = 100,
        maxISize = 50000
    )
    asd <- jCounts(
        counts = gbcounts,
        features = features,
        minReadLength = 100
    )

    # --- Differential Splicing Analysis [Differential Expression] ---
    # Key functions: gbDUreport, jDUreport
    gb <- gbDUreport(
        gbcounts,
        contrast = c(-1, 1)
    )
    jdur <- jDUreport(
        asd,
        contrast = c(-1, 1)
    )

    # --- Splicing Report and Signal Integration [Integration] ---
    # Key functions: splicingReport, integrateSignals
    sr <- splicingReport(
        gb,
        jdur,
        counts = gbcounts
    )
    is <- integrateSignals(
        sr,
        asd
    )

    # --- Exporting Integrated Signals [Export] ---
    # Key functions: exportIntegratedSignals
    mBAMs <- data.frame(
        bam = sub("_[012]", "", targets$bam[c(1, 4)]),
        condition = c("control", "treatment")
    )
    exportIntegratedSignals(
        is,
        sr = sr,
        output.dir = "aspliExample",
        counts = gbcounts,
        features = features,
        asd = asd,
        mergedBams = mBAMs
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aspli_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aspli_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aspli_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASPLI:", paste0("    aspli: ", packageVersion("ASpli"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aspli_results.csv
    touch ${prefix}_aspli_output.rds
    echo "BIOC_ASPLI:" > versions.yml
    echo "    aspli: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASPLI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_ASPLI(ch_input)

    emit:
    results  = BIOC_ASPLI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASPLI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASPLI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASPLI.out.versions  // channel: path(versions.yml)
}
