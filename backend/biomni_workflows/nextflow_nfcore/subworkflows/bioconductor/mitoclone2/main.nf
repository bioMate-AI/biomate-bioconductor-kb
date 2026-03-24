#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mitoClone2
// This package primarily identifies variants in mitochondrial genomes from BAM alignment files. It fil
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mitoClone2/inst/doc/clustering.R
// Upstream  : pheatmap
// Downstream: none
//
// Install: BiocManager::install("mitoClone2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MITOCLONE2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mitoclone2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mitoclone2:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mitoclone2:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mitoclone2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mitoclone2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mitoclone2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mitoClone2)
    library(jsonlite)

    # --- tempdir [] ---
    # Key functions: tempdir, varCluster
    tmpd <- tempdir()
    dir.create(paste0(tmpd,'/p1'))
    P1 <- varCluster(P1, tempfolder=paste0(tmpd,'/p1'),method='SCITE')
    # --- cluster Metaclones [] ---
    # Key functions: clusterMetaclones
    P1 <- clusterMetaclones(P1, min.lik = 1)
    # --- plot Clones [] ---
    # Key functions: plotClones
    m2c <- mitoClone2:::getMut2Clone(P1)
    print(m2c)
    m2c[c("X2537GA","X14462GA")] <- as.integer(6)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mitoclone2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mitoclone2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mitoclone2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MITOCLONE2:", paste0("    mitoclone2: ", packageVersion("mitoClone2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mitoclone2_results.csv
    touch ${prefix}_mitoclone2_output.rds
    echo "BIOC_MITOCLONE2:" > versions.yml
    echo "    mitoclone2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MITOCLONE2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MITOCLONE2(ch_input)

    emit:
    results  = BIOC_MITOCLONE2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MITOCLONE2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MITOCLONE2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MITOCLONE2.out.versions  // channel: path(versions.yml)
}
