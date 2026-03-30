#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ldblock
// Define data structures for linkage disequilibrium measures in populations.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ldblock/inst/doc/ldblock.R
// Upstream  : GenomeInfoDb, Matrix, gwascat
// Downstream: none
//
// Install: BiocManager::install("ldblock")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LDBLOCK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ldblock"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ldblock:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ldblock:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ldblock_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ldblock_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ldblock_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ldblock)
    library(jsonlite)

    # --- image [] ---
    # Key functions: image
    library(Matrix)
    image(ceu17@ldmat[1:400,1:400],
    col.reg=heat.colors(120), colorkey=TRUE, useRaster=TRUE)
    # --- seqlevels Style [] ---
    # Key functions: seqlevelsStyle, seqlevels
    library(gwascat)
    load(system.file("legacy/ebicat37.rda", package="gwascat"))
    seqlevelsStyle(ebicat37) = "NCBI"  # noop?

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ldblock_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ldblock_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ldblock_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LDBLOCK:", paste0("    ldblock: ", packageVersion("ldblock"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ldblock_results.csv
    touch ${prefix}_ldblock_output.rds
    echo "BIOC_LDBLOCK:" > versions.yml
    echo "    ldblock: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LDBLOCK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LDBLOCK(ch_input)

    emit:
    results  = BIOC_LDBLOCK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LDBLOCK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LDBLOCK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LDBLOCK.out.versions  // channel: path(versions.yml)
}
