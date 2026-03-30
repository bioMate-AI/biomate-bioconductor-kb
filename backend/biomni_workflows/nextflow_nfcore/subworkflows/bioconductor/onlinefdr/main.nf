#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: onlineFDR
// This package allows users to control the false discovery rate (FDR) or familywise error rate (FWER) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/onlineFDR/inst/doc/advanced-usage.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("onlineFDR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONLINEFDR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-onlinefdr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-onlinefdr:2.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-onlinefdr:2.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_onlinefdr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_onlinefdr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_onlinefdr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(LOND)
    library(LORD)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: LOND
    set.seed(1); results.indep <- LOND(sample.df)    # for independent p-values
    set.seed(1); results.dep <- LOND(sample.df, dep=TRUE)   # for dependent p-values
    # compare adjusted significance thresholds
    cbind(independent = results.indep$alphai, dependent = results.dep$alphai)
    #>        independent    dependent
    # --- Code Block 2 [] ---
    # Key functions: LORD
    set.seed(1); results.LORD.plus <- LORD(sample.df)
    set.seed(1); results.LORD3 <- LORD(sample.df, version=3)
    set.seed(1); results.LORD.discard <- LORD(sample.df, version='discard')
    set.seed(1); results.LORD.dep <- LORD(sample.df, version='dep')
    # compare adjusted significance thresholds

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_onlinefdr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_onlinefdr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_onlinefdr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ONLINEFDR:", paste0("    onlinefdr: ", packageVersion("onlineFDR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_onlinefdr_results.csv
    touch ${prefix}_onlinefdr_output.rds
    echo "BIOC_ONLINEFDR:" > versions.yml
    echo "    onlinefdr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ONLINEFDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ONLINEFDR(ch_input)

    emit:
    results  = BIOC_ONLINEFDR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ONLINEFDR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ONLINEFDR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ONLINEFDR.out.versions  // channel: path(versions.yml)
}
