#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEDME
// MEDME allows the prediction of absolute and relative methylation levels based on measures obtained b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEDME/inst/doc/MEDME.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MEDME")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEDME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-medme"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-medme:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-medme:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_medme_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_medme_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_medme_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AMS)
    library(CGcount)
    library(MEDME)
    library(RMS)
    library(jsonlite)

    # --- Medmeload [] ---
    # Key functions: data
    library(MEDME)
    data(testMEDMEset)
    # --- Medmedata [] ---
    # Key functions: logR
    logR(testMEDMEset[1:5,])
    # --- Medmesmooth [] ---
    # Key functions: smooth
    testMEDMEset = smooth(data = testMEDMEset, wsize = 1000, wFunction = 'linear')
    # --- Medmecpg [] ---
    # Key functions: CGcount
    library(BSgenome.Hsapiens.UCSC.hg18)
    testMEDMEset = CGcount(data = testMEDMEset)
    # --- Medmemodel [] ---
    # Key functions: MEDME
    MEDMEmodel = MEDME(data = testMEDMEset, sample = 1)
    # --- Medmerun [] ---
    # Key functions: predict
    testMEDMEset = MEDME.predict(data = testMEDMEset, MEDMEfit = MEDMEmodel, MEDMEextremes = c(1,32), wsize = 1000, wFunction='linear')
    # --- Medmesee [] ---
    # Key functions: smoothed, AMS, RMS
    smoothed(testMEDMEset)[1:3,]
    AMS(testMEDMEset)[1:3,]
    RMS(testMEDMEset)[1:3,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_medme_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_medme_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_medme_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEDME:", paste0("    medme: ", packageVersion("MEDME"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_medme_results.csv
    touch ${prefix}_medme_output.rds
    echo "BIOC_MEDME:" > versions.yml
    echo "    medme: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEDME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEDME(ch_input)

    emit:
    results  = BIOC_MEDME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEDME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEDME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEDME.out.versions  // channel: path(versions.yml)
}
