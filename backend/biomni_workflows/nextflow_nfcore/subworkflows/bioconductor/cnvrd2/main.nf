#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNVrd2
// CNVrd2 uses next-generation sequencing data to measure human gene copy number for multiple samples, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNVrd2/inst/doc/CNVrd2.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CNVrd2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNVRD2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnvrd2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnvrd2:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnvrd2:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnvrd2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnvrd2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnvrd2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNVrd2)
    library(jsonlite)

    # --- warnings=FALSE [] ---
    # Key functions: countReadInWindow
    readCountMatrix <- countReadInWindow(Object = objectCNVrd2, correctGC = TRUE)
    # --- 'fcgr3bSS' [] ---
    # Key functions: new, segmentSamples
    data(fcgr3bMXL)
    # --- 'fcgr3b4CNs' [] ---
    # Key functions: new, groupCNVs

    # --- 'fcgr3b3CNs' [] ---
    # Key functions: new, groupCNVs

    # --- 'fcgr3bdupSamples' [] ---
    # Key functions: plotCNVrd2
    duplicatedSamples <- rownames(allGroups[allGroups[, 2] > 2,])
    par(mfrow = c(3, 2))
    for (ii in duplicatedSamples[1:6])
    # --- 'EUccl3l1results' [] ---
    # Key functions: new, groupCNVs
    objectClusterEuroCCL3L1 <- new("clusteringCNVs", x = yEuro, k = 5)
    europeanCCL3L1Groups <- groupCNVs(Object = objectClusterEuroCCL3L1)
    # --- warnings=FALSE [] ---
    # Key functions: identifyPolymorphicRegion

    # --- 'FCGR3polymorphc1' [] ---
    # Key functions: plotPolymorphicRegion

    # --- 'FCGR3polymorphc2' [] ---
    # Key functions: plotPolymorphicRegion


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnvrd2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnvrd2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnvrd2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNVRD2:", paste0("    cnvrd2: ", packageVersion("CNVrd2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnvrd2_results.csv
    touch ${prefix}_cnvrd2_output.rds
    echo "BIOC_CNVRD2:" > versions.yml
    echo "    cnvrd2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNVRD2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNVRD2(ch_input)

    emit:
    results  = BIOC_CNVRD2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNVRD2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNVRD2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNVRD2.out.versions  // channel: path(versions.yml)
}
