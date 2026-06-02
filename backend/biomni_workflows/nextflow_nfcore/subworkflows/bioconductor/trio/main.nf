#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: trio
// Testing SNPs and SNP interactions with a genotypic TDT. This package furthermore contains functions 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/trio/inst/doc/trio.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("trio")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-trio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-trio:3.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-trio:3.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_trio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_trio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_trio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(trio)
    library(jsonlite)

    # --- Transmission Disequilibrium Testing [] ---
    # Key functions: tdt, colTDT, colTDTmaxStat, colTDTmaxTest
    data(trio.data)
    single_tdt <- tdt(mat.test[, 1], model = "dominant")
    col_tdt_results <- colTDT(mat.test)
    max_stat_results <- colTDTmaxStat(mat.test)
    max_test_results <- colTDTmaxTest(mat.test, perm = 100)


    # --- Interaction Analysis [] ---
    # Key functions: colGxG, colGxE, getGxEstats
    data(trio.data)
    genes_vector <- paste("G", rep(1:2, c(2, 4)), sep = "")
    gxg_results <- colGxG(mat.test, genes = genes_vector)
    sex_covariate <- rep(0:1, each = 50)
    gxe_results <- colGxE(mat.test, sex_covariate)
    top_gxe <- getGxEstats(gxe_results, top = 3, sortBy = "lrt2df")


    # --- Alternative Association Testing [] ---
    # Key functions: allelicTDT, scoreTDT
    data(trio.data)
    allelic_results <- allelicTDT(mat.test, correct = TRUE)
    score_results <- scoreTDT(mat.test)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_trio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_trio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_trio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRIO:", paste0("    trio: ", packageVersion("trio"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trio_results.csv
    touch ${prefix}_trio_output.rds
    echo "BIOC_TRIO:" > versions.yml
    echo "    trio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRIO(ch_input)

    emit:
    results  = BIOC_TRIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRIO.out.versions  // channel: path(versions.yml)
}
