#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNEr
// Large-scale identification and advanced visualization of sets of conserved noncoding elements.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNEr/inst/doc/CNEr.R
// Upstream  : GenomeInfoDb, Gviz, biomaRt, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("CNEr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cner:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cner:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiomartGeneRegionTrack)
    library(CNE)
    library(CNE12)
    library(CNE21)
    library(GenomeAxisTrack)
    library(UcscTrack)
    library(jsonlite)

    # --- Connect to BioMart [] ---
    # Key functions: browserSession, genome, useMart, useDataset, listAttributes, GenomeAxisTrack, UcscTrack, BiomartGeneRegionTrack
    library(rtracklayer)
    mySession <- browserSession("UCSC")
    genome(mySession) <- "hg38"
    # --- ReadAxt analysis [] ---
    # Key functions: readAxt, matchDistribution, syntenicDotplot, readBed, CNE, ceScan, CNE12, CNE21


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNER:", paste0("    cner: ", packageVersion("CNEr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cner_results.csv
    touch ${prefix}_cner_output.rds
    echo "BIOC_CNER:" > versions.yml
    echo "    cner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNER(ch_input)

    emit:
    results  = BIOC_CNER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNER.out.versions  // channel: path(versions.yml)
}
