#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pipeFrame
// pipeFrame is an R package for building a componentized bioinformatics pipeline. Each step in this pi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pipeFrame/inst/doc/pipeFrame.R
// Upstream  : BSgenome, magrittr, rtracklayer
// Downstream: esATAC
//
// Install: BiocManager::install("pipeFrame")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PIPEFRAME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pipeframe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pipeframe:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pipeframe:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pipeframe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pipeframe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pipeframe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pipeFrame)
    library(jsonlite)

    # --- Reference Genome Configuration [] ---
    # Key functions: setGenome, getGenome
    setGenome("hg19")
    current_genome <- getGenome()


    # --- Pipeline Graph Construction [] ---
    # Key functions: addEdges, printMap
    addEdges(edges = c("RandomRegionOnGenome", "OverlappedRandomRegion"),
             argOrder = 1)
    printMap()


    # --- Step Definition [] ---
    # Key functions: runWithFinishCheck
    checkAndInstall <- function() {
        runWithFinishCheck(func = checkAndInstallBSgenome,
                           refName = "bsgenome")
    }

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pipeframe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pipeframe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pipeframe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PIPEFRAME:", paste0("    pipeframe: ", packageVersion("pipeFrame"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pipeframe_results.csv
    touch ${prefix}_pipeframe_output.rds
    echo "BIOC_PIPEFRAME:" > versions.yml
    echo "    pipeframe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PIPEFRAME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PIPEFRAME(ch_input)

    emit:
    results  = BIOC_PIPEFRAME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PIPEFRAME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PIPEFRAME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PIPEFRAME.out.versions  // channel: path(versions.yml)
}
