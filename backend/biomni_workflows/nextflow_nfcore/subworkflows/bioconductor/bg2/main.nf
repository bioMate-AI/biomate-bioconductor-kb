#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BG2
// This package is built to perform GWAS analysis for non-Gaussian data using BG2. The BG2 method uses 
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/BG2/inst/doc/BG2.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BG2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BG2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bg2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bg2:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bg2:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bg2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bg2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bg2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BG2)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: diag
    n <- length(Y_poisson)
    covariance <- list()
    covariance[[1]] <- kinship
    covariance[[2]] <- diag(1, nrow = n, ncol = n)
    # --- Code Block 2 [] ---
    # Key functions: BG2
    set.seed(1330)
    output_poisson <- BG2(Y=Y_poisson, SNPs=SNPs, Fixed = NULL,
                          Covariance=covariance, Z=NULL, family="poisson",
                          replicates=4, Tau="uniform",FDR_Nominal = 0.05,
                          maxiterations = 4000, runs_til_stop = 400)
    # --- Code Block 4 [] ---
    # Key functions: BG2
    set.seed(1330)
    output_binary <- BG2(Y=Y_binary, SNPs=SNPs, Fixed = NULL,
                         Covariance=covariance, Z=NULL, family="bernoulli",
                         replicates=NULL, Tau="IG",FDR_Nominal = 0.05,
                         maxiterations = 4000, runs_til_stop = 400)
    # --- Code Block 5 [] ---
    # Key functions: 1, namespace
    sessionInfo()
    #> R version 4.4.1 (2024-06-14)
    #> Platform: x86_64-pc-linux-gnu
    #> Running under: Ubuntu 24.04.1 LTS
    #>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bg2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bg2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bg2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BG2:", paste0("    bg2: ", packageVersion("BG2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bg2_results.csv
    touch ${prefix}_bg2_output.rds
    echo "BIOC_BG2:" > versions.yml
    echo "    bg2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BG2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BG2(ch_input)

    emit:
    results  = BIOC_BG2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BG2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BG2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BG2.out.versions  // channel: path(versions.yml)
}
