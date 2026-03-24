#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rbwa
// Provides an R wrapper for BWA alignment algorithms. Both BWA-backtrack and BWA-MEM are available. Co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rbwa/inst/doc/Rbwa.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Rbwa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBWA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbwa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbwa:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbwa:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbwa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbwa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbwa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rbwa)
    library(jsonlite)

    # --- Bwa build index analysis [] ---
    # Key functions: tempdir, bwa_build_index, bwa_aln, bwa_sam, strtrim, xa2multi, bwa_mem
    xa2multi(file.path(dir, "output.sam"),
    file.path(dir, "output.multi.sam"))
    strtrim(readLines(file.path(dir, "output.multi.sam")), 65)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbwa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbwa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbwa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBWA:", paste0("    rbwa: ", packageVersion("Rbwa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbwa_results.csv
    touch ${prefix}_rbwa_output.rds
    echo "BIOC_RBWA:" > versions.yml
    echo "    rbwa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBWA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBWA(ch_input)

    emit:
    results  = BIOC_RBWA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBWA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBWA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBWA.out.versions  // channel: path(versions.yml)
}
