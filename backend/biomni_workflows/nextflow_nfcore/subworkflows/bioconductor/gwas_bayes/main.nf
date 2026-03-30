#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GWAS.BAYES
// This package is built to perform GWAS analysis using Bayesian techniques. Currently, GWAS.BAYES has 
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/GWAS.BAYES/inst/doc/Vignette_BICOSS.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GWAS.BAYES")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GWAS_BAYES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gwas_bayes"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gwas.bayes:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gwas.bayes:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gwas_bayes_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gwas_bayes_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gwas_bayes_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BICOSS)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: BICOSS
    BICOSS_P3D <- BICOSS(Y = Y, SNPs = SNPs,
                         kinship = kinship,FDR_Nominal = 0.05,P3D = TRUE,
                         maxiterations = 400,runs_til_stop = 40)
    BICOSS_P3D$best_model
    #> [1] 1268 1350 2250 3150 4950 5276 5850 8550
    # --- Code Block 2 [] ---
    # Key functions: BICOSS
    BICOSS_Exact <- BICOSS(Y = Y, SNPs = SNPs,
                           kinship = kinship,FDR_Nominal = 0.05,P3D = FALSE,
                           maxiterations = 400,runs_til_stop = 40)
    BICOSS_Exact$best_model
    #> [1] 1268 1350 2250 3150 4950 5276 5850 8550
    # --- Code Block 4 [] ---
    # Key functions: 1, namespace
    sessionInfo()
    #> R version 4.4.1 (2024-06-14)
    #> Platform: x86_64-pc-linux-gnu
    #> Running under: Ubuntu 24.04.1 LTS
    #>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gwas_bayes_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gwas_bayes_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gwas_bayes_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GWAS_BAYES:", paste0("    gwas_bayes: ", packageVersion("GWAS.BAYES"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwas_bayes_results.csv
    touch ${prefix}_gwas_bayes_output.rds
    echo "BIOC_GWAS_BAYES:" > versions.yml
    echo "    gwas_bayes: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GWAS_BAYES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GWAS_BAYES(ch_input)

    emit:
    results  = BIOC_GWAS_BAYES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GWAS_BAYES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GWAS_BAYES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GWAS_BAYES.out.versions  // channel: path(versions.yml)
}
