#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: escheR
// The creation of effective visualizations is a fundamental component of data analysis. In biomedical 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/escheR/inst/doc/SRT_eg.R
// Upstream  : devtools, ggpubr, STexampleData, scater, scran
// Downstream: none
//
// Install: BiocManager::install("escheR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ESCHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-escher"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-escher:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-escher:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_escher_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_escher_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_escher_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(escheR)
    library(Visium_humanDLPFC)
    library(jsonlite)

    # --- Adding Spatial Fill and Ground Layers [] ---
    # Key functions: make_escheR, add_fill, add_ground
    p <- make_escheR(spe)
    p1 <- add_fill(p, var = "cell_count")
    p2 <- add_ground(p1, var = "ground_truth", stroke = 0.5)


    # --- Multi-layer Spatial Annotation [] ---
    # Key functions: make_escheR, add_fill, add_ground, add_symbol
    spe$counts_MOBP <- counts(spe)[1, ]
    p <- make_escheR(spe)
    p <- add_fill(p, var = "counts_MOBP")
    p <- add_ground(p, var = "ground_truth", stroke = 0.5)
    p <- add_symbol(p, var = "ground_truth", size = 0.2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_escher_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_escher_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_escher_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ESCHER:", paste0("    escher: ", packageVersion("escheR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_escher_results.csv
    touch ${prefix}_escher_output.rds
    echo "BIOC_ESCHER:" > versions.yml
    echo "    escher: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ESCHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_ESCHER(ch_input)

    emit:
    results  = BIOC_ESCHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ESCHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ESCHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ESCHER.out.versions  // channel: path(versions.yml)
}
