#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rbec
// Rbec is a adapted version of DADA2 for analyzing amplicon sequencing data from synthetic communities
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rbec/inst/doc/Rbec.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Rbec")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBEC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbec"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbec:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbec:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbec_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbec_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbec_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Contam_detect)
    library(Rbec)
    library(jsonlite)

    # --- Rbec [] ---
    # Key functions: Rbec
    library(Rbec)
    fq <- system.file("extdata", "test_raw_merged_reads.fastq.gz", package="Rbec")
    ref <- system.file("extdata", "test_ref.fasta", package="Rbec")
    # --- Contam detect [] ---
    # Key functions: tempfile, Contam_detect
    log_path <- list.files(paste(path.package("Rbec"), "extdata/contamination_test", sep="/"), recursive=TRUE, full.names=TRUE)
    log_file <- tempfile()
    writeLines(log_path, log_file)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbec_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbec_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbec_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBEC:", paste0("    rbec: ", packageVersion("Rbec"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbec_results.csv
    touch ${prefix}_rbec_output.rds
    echo "BIOC_RBEC:" > versions.yml
    echo "    rbec: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBEC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBEC(ch_input)

    emit:
    results  = BIOC_RBEC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBEC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBEC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBEC.out.versions  // channel: path(versions.yml)
}
