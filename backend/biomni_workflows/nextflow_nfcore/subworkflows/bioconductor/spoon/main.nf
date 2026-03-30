#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: spoon
// This package addresses the mean-variance relationship in spatially resolved transcriptomics data. Pr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/spoon/inst/doc/spoon.R
// Upstream  : BRISC, BiocParallel, Matrix, STexampleData, SpatialExperiment
// Downstream: none
//
// Install: BiocManager::install("spoon")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPOON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spoon"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spoon:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spoon:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spoon_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spoon_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spoon_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MulticoreParam)
    library(Visium_mouseCoronal)
    library(jsonlite)

    # --- Visium Mousecoronal [] ---
    # Key functions: Visium_mouseCoronal
    ---------------------------------------------------------------------
    library(nnSVG)
    library(STexampleData)
    library(SpatialExperiment)
    library(BRISC)
    # --- Coldata [] ---
    # Key functions: colData, filter_genes, logcounts, computeLibraryFactors, logNormCounts, sample
    ---------------------------------------------------------------------
    # keep spots over tissue
    spe <- spe[, colData(spe)$in_tissue == 1]
    # filter out low quality genes
    spe <- filter_genes(spe)
    # --- Generate Weights [] ---
    # Key functions: generate_weights, MulticoreParam
    ---------------------------------------------------------------------
    weights <- generate_weights(input = spe,
                                stabilize = TRUE,
                                BPPARAM = MulticoreParam(workers = 1,
                                                         RNGseed = 4))
    # --- Weighted Nnsvg [] ---
    # Key functions: weighted_nnSVG, MulticoreParam
    ---------------------------------------------------------------------
    spe <- weighted_nnSVG(input = spe,
                          w = weights,
                          BPPARAM = MulticoreParam(workers = 1, RNGseed = 5))
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    # display results
    rowData(spe)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spoon_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spoon_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spoon_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPOON:", paste0("    spoon: ", packageVersion("spoon"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spoon_results.csv
    touch ${prefix}_spoon_output.rds
    echo "BIOC_SPOON:" > versions.yml
    echo "    spoon: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPOON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPOON(ch_input)

    emit:
    results  = BIOC_SPOON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPOON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPOON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPOON.out.versions  // channel: path(versions.yml)
}
