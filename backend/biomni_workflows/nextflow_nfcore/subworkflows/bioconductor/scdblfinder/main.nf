#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scDblFinder
// The scDblFinder package gathers various methods for the detection and handling of doublets/multiplet
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scDblFinder/inst/doc/computeDoubletDensity.R
// Upstream  : BiocStyle, bluster, scRNAseq, scater, scran
// Downstream: OSCA.advanced
//
// Install: BiocManager::install("scDblFinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCDBLFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scdblfinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scdblfinder:1.20.2--r44_0' :
        'quay.io/biocontainers/bioconductor-scdblfinder:1.20.2--r44_0'}"

    input:
    tuple val(meta), path(seurat_object)

    output:
    tuple val(meta), path("${meta.id}_scdblfinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scdblfinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scdblfinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BachMammaryData)
    library(jsonlite)

    # --- Bachmammarydata [] ---
    # Key functions: BachMammaryData, sample
    ---------------------------------------------------------------------
    library(scRNAseq)
    sce <- BachMammaryData(samples="G_1")
    set.seed(1001)
    sce <- sce[,sample(ncol(sce), 1000)]
    # --- Lognormcounts [] ---
    # Key functions: logNormCounts, modelGeneVar, getTopHVGs, runPCA, runTSNE
    ---------------------------------------------------------------------
    library(scuttle)
    sce <- logNormCounts(sce)
    library(scran)
    dec <- modelGeneVar(sce)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scdblfinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scdblfinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scdblfinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCDBLFINDER:", paste0("    scdblfinder: ", packageVersion("scDblFinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scdblfinder_results.csv
    touch ${prefix}_scdblfinder_output.rds
    echo "BIOC_SCDBLFINDER:" > versions.yml
    echo "    scdblfinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCDBLFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(seurat_object) ]

    main:
    BIOC_SCDBLFINDER(ch_input)

    emit:
    results  = BIOC_SCDBLFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCDBLFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCDBLFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCDBLFINDER.out.versions  // channel: path(versions.yml)
}
