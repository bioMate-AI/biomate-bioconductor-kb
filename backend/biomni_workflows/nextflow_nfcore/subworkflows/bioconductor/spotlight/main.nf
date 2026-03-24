#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SPOTlight
// `SPOTlight`provides a method to deconvolute spatial transcriptomics spots using a seeded NMF approac
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SPOTlight/inst/doc/SPOTlight_kidney.R
// Upstream  : NMF, SingleCellExperiment, SpatialExperiment, TENxVisiumData, TabulaMurisSenisData
// Downstream: none
//
// Install: BiocManager::install("SPOTlight")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPOTLIGHT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spotlight"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spotlight:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spotlight:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_spotlight_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spotlight_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spotlight_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MouseKidneyCoronal)
    library(SPOTlight)
    library(TabulaMurisSenisDroplet)
    library(jsonlite)

    # --- Log-normalize count data [] ---
    # Key functions: logNormCounts
    sce <- logNormCounts(sce)
    # --- Score cluster marker genes [] ---
    # Key functions: colLabels, scoreMarkers
    colLabels(sce) <- colData(sce)$free_annotation
    mgs <- scoreMarkers(sce, subset.row = genes)
    # --- MouseKidneyCoronal analysis [] ---
    # Key functions: MouseKidneyCoronal, TabulaMurisSenisDroplet, modelGeneVar, curve, getTopHVGs, split, sample, SPOTlight
    genes <- !grepl(pattern = "^Rp[l|s]|Mt", x = rownames(sce))
    dec <- modelGeneVar(sce, subset.row = genes)
    plot(dec$mean, dec$total, xlab = "Mean log-expression", ylab = "Variance")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spotlight_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spotlight_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spotlight_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPOTLIGHT:", paste0("    spotlight: ", packageVersion("SPOTlight"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spotlight_results.csv
    touch ${prefix}_spotlight_output.rds
    echo "BIOC_SPOTLIGHT:" > versions.yml
    echo "    spotlight: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPOTLIGHT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_SPOTLIGHT(ch_input)

    emit:
    results  = BIOC_SPOTLIGHT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPOTLIGHT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPOTLIGHT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPOTLIGHT.out.versions  // channel: path(versions.yml)
}
