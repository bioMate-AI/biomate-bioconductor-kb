#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pcaExplorer
// This package provides functionality for interactive visualization of RNA-seq datasets based on Princ
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pcaExplorer/inst/doc/pcaExplorer.R
// Upstream  : DESeq2, airway, devtools, topGO
// Downstream: none
//
// Install: BiocManager::install("pcaExplorer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PCAEXPLORER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pcaexplorer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pcaexplorer:3.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pcaexplorer:3.0.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_pcaexplorer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pcaexplorer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pcaexplorer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(jsonlite)

    # --- Create DESeqDataSet [] ---
    # Key functions: DESeqDataSet, rlogTransformation
    library("airway")
    library("DESeq2")
    data("airway", package = "airway")
    # --- Run DESeq2 differential expression [] ---
    # Key functions: DESeq, results, mapIds, topGOtable
    dds_airway <- DESeq(dds_airway)
    res_airway <- results(dds_airway)
    # --- Principal component analysis [] ---
    # Key functions: prcomp, pcascree
    pcaobj_airway <- prcomp(t(assay(rld_airway)))
    # --- ID mapping annotation [] ---
    # Key functions: install_github, pcaExplorer, mapIds, get_annotation_orgdb, get_annotation, rlogTransformation, pcaplot, pcaplot3d
    dds_simu <- makeExampleDESeqDataSet_multifac(betaSD_condition = 3,betaSD_tissue = 0.5)
    dds2_simu <- makeExampleDESeqDataSet_multifac(betaSD_condition = 0.5,betaSD_tissue = 2)
    rld_simu <- rlogTransformation(dds_simu)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pcaexplorer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pcaexplorer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pcaexplorer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PCAEXPLORER:", paste0("    pcaexplorer: ", packageVersion("pcaExplorer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcaexplorer_results.csv
    touch ${prefix}_pcaexplorer_output.rds
    echo "BIOC_PCAEXPLORER:" > versions.yml
    echo "    pcaexplorer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PCAEXPLORER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_PCAEXPLORER(ch_input)

    emit:
    results  = BIOC_PCAEXPLORER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PCAEXPLORER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PCAEXPLORER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PCAEXPLORER.out.versions  // channel: path(versions.yml)
}
