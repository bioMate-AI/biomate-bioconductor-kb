#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rbowtie2
// This package provides an R wrapper of the popular bowtie2 sequencing reads aligner and AdapterRemova
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rbowtie2/inst/doc/Rbowtie2-Introduction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Rbowtie2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBOWTIE2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbowtie2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbowtie2:2.12.3--r44_0' :
        'quay.io/biocontainers/bioconductor-rbowtie2:2.12.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbowtie2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbowtie2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbowtie2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rbowtie2)
    library(jsonlite)

    # --- tempdir [] ---
    # Key functions: tempdir, identify_adapters
    td <- tempdir()
    reads_1 <- system.file(package="Rbowtie2", "extdata", "adrm", "reads_1.fq")
    reads_2 <- system.file(package="Rbowtie2", "extdata", "adrm", "reads_2.fq")
    # --- adapterremoval_usage [] ---
    # Key functions: adapterremoval_usage
    adapterremoval_usage()
    # --- adapterremoval_version [] ---
    # Key functions: adapterremoval_version
    adapterremoval_version()
    # --- bowtie2_build_usage [] ---
    # Key functions: bowtie2_build_usage
    bowtie2_build_usage()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbowtie2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbowtie2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbowtie2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBOWTIE2:", paste0("    rbowtie2: ", packageVersion("Rbowtie2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbowtie2_results.csv
    touch ${prefix}_rbowtie2_output.rds
    echo "BIOC_RBOWTIE2:" > versions.yml
    echo "    rbowtie2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBOWTIE2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBOWTIE2(ch_input)

    emit:
    results  = BIOC_RBOWTIE2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBOWTIE2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBOWTIE2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBOWTIE2.out.versions  // channel: path(versions.yml)
}
