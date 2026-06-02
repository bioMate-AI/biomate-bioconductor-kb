#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: icetea
// icetea (Integrating Cap Enrichment with Transcript Expression Analysis) provides functions for end-t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/icetea/inst/doc/mapcap_analysis.R
// Upstream  : Rsubread, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("icetea")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICETEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-icetea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-icetea:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-icetea:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_icetea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_icetea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_icetea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(icetea)
    library(jsonlite)

    # --- Demultiplexing Fastq Files [] ---
    # Key functions: demultiplexFASTQ
    dir.create("splitting")
    cs <- demultiplexFASTQ(cs,
                           max_mismatch = 1,
                           outdir = "splitting",
                           ncores = 1)


    # --- PCR Duplicate Filtering [] ---
    # Key functions: exampleCSobject, filterDuplicates
    cs <- exampleCSobject()
    dir.create("removedup")
    cs <- filterDuplicates(cs, outdir = "removedup")


    # --- Transcription Start Site Detection [] ---
    # Key functions: exampleCSobject, detectTSS, exportTSS
    cs <- exampleCSobject()
    dir.create("tssCalling")
    cs <- detectTSS(cs,
                    groups = c("wt", "wt", "mut", "mut"),
                    outfile_prefix = "tssCalling/testTSS",
                    restrictChr = "X",
                    ncores = 1)
    exportTSS(cs, merged = TRUE, outfile_prefix = "tssCalling/testTSS")


    # --- TSS Quality Control and Annotation [] ---
    # Key functions: plotReadStats, plotTSSprecision, annotateTSS
    cs <- exampleCSobject()
    plotReadStats(cs, plotValue = "numbers", plotType = "dodge")
    plotReadStats(cs, plotValue = "proportions", plotType = "stack")
    tssfile <- system.file("extdata", "testTSS_merged.bed", package = "icetea")
    txdb <- TxDb.Dmelanogaster.UCSC.dm6.ensGene::TxDb.Dmelanogaster.UCSC.dm6.ensGene
    transcripts <- GenomicFeatures::transcripts(txdb)
    plotTSSprecision(reference = transcripts,
                     detectedTSS = tssfile,
                     sampleNames = "testsample")
    outdf <- annotateTSS(tssBED = tssfile,
                         txdb = txdb,
                         plotValue = "number",
                         outFile = NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_icetea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_icetea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_icetea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ICETEA:", paste0("    icetea: ", packageVersion("icetea"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_icetea_results.csv
    touch ${prefix}_icetea_output.rds
    echo "BIOC_ICETEA:" > versions.yml
    echo "    icetea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ICETEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ICETEA(ch_input)

    emit:
    results  = BIOC_ICETEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ICETEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ICETEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ICETEA.out.versions  // channel: path(versions.yml)
}
