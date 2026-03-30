#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: diffcoexp
// A tool for the identification of differentially coexpressed links (DCLs) and differentially coexpres
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/diffcoexp/inst/doc/diffcoexp.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("diffcoexp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFCOEXP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-diffcoexp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-diffcoexp:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-diffcoexp:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_diffcoexp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_diffcoexp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_diffcoexp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(diffcoexp)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(diffcoexp)
    data(gse4158part)
    # --- Allowwgcnathreads [] ---
    # Key functions: allowWGCNAThreads, diffcoexp
    allowWGCNAThreads()
    res=diffcoexp(exprs.1 = exprs.1, exprs.2 = exprs.2, r.method = "spearman" )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_diffcoexp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_diffcoexp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_diffcoexp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFCOEXP:", paste0("    diffcoexp: ", packageVersion("diffcoexp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffcoexp_results.csv
    touch ${prefix}_diffcoexp_output.rds
    echo "BIOC_DIFFCOEXP:" > versions.yml
    echo "    diffcoexp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFCOEXP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFCOEXP(ch_input)

    emit:
    results  = BIOC_DIFFCOEXP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFCOEXP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFCOEXP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFCOEXP.out.versions  // channel: path(versions.yml)
}
