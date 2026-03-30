#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PLPE
// This package performs tests for paired high-throughput data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PLPE/inst/doc/PLPE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PLPE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plpe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plpe:1.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plpe:1.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plpe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plpe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plpe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PLPE)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: exprs
    library(PLPE)
    data(plateletSet)
    x <- exprs(plateletSet)
    x <- log2(x) #and any normalization
    cond <- c(1, 2, 1, 2, 1, 2)   #two different samples
    # --- Paired [] ---
    # Key functions: paired, fdr
    out <- lpe.paired(x=x, design=design, q=0.1,data.type="ms") #Compute test statistics
    out.fdr <- lpe.paired.fdr(x, obj=out) #Compute FDRs
    out$test.out[1:10,]
    out.fdr$FDR[1:10,]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plpe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plpe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plpe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLPE:", paste0("    plpe: ", packageVersion("PLPE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plpe_results.csv
    touch ${prefix}_plpe_output.rds
    echo "BIOC_PLPE:" > versions.yml
    echo "    plpe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLPE(ch_input)

    emit:
    results  = BIOC_PLPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLPE.out.versions  // channel: path(versions.yml)
}
