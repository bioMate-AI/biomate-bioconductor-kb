#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneGA
// R based Genetic algorithm for gene expression optimization by considering both mRNA secondary struct
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneGA/inst/doc/GeneGA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GeneGA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEGA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genega"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genega:1.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genega:1.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genega_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genega_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genega_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneGA)
    library(jsonlite)

    # --- Genega [] ---
    # Key functions: GeneGA
    GeneGA.result=GeneGA(sequence=seq, popSize=40, iters=150, crossoverRate=0.3, mutationChance=0.05, region=c(1,60), organism="ec", showGeneration=FALSE)
    # --- Plotgenega [] ---
    # Key functions: plotGeneGA
    plotGeneGA(GeneGA.result, type=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genega_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genega_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genega_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEGA:", paste0("    genega: ", packageVersion("GeneGA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genega_results.csv
    touch ${prefix}_genega_output.rds
    echo "BIOC_GENEGA:" > versions.yml
    echo "    genega: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEGA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEGA(ch_input)

    emit:
    results  = BIOC_GENEGA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEGA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEGA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEGA.out.versions  // channel: path(versions.yml)
}
