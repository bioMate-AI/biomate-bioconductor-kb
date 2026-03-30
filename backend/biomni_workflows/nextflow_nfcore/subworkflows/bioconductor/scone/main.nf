#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scone
// SCONE is an R package for comparing and ranking the performance of different normalization schemes f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scone/inst/doc/PsiNorm.R
// Upstream  : Seurat, SingleCellExperiment, TENxPBMCData, cluster, scRNAseq
// Downstream: none
//
// Install: BiocManager::install("scone")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCONE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scone"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scone:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scone:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_scone_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scone_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scone_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PsiNorm)
    library(TENxPBMCData)
    library(jsonlite)

    # --- Log-normalize count data [] ---
    # Key functions: PsiNorm, logNormCounts
    library(Seurat)
    sce <- PsiNorm(sce)
    sce <- logNormCounts(sce)
    # --- T E Nx P B M C Data [] ---
    # Key functions: TENxPBMCData
    library(TENxPBMCData)
    sce <- TENxPBMCData("pbmc4k")
    # --- counts [] ---
    # Key functions: counts
    counts(sce)
    seed(counts(sce))
    # --- Log-normalize count data [] ---
    # Key functions: PsiNorm, logNormCounts
    sce<-PsiNorm(sce)
    sce<-logNormCounts(sce)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scone_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scone_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scone_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCONE:", paste0("    scone: ", packageVersion("scone"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scone_results.csv
    touch ${prefix}_scone_output.rds
    echo "BIOC_SCONE:" > versions.yml
    echo "    scone: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCONE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_SCONE(ch_input)

    emit:
    results  = BIOC_SCONE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCONE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCONE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCONE.out.versions  // channel: path(versions.yml)
}
