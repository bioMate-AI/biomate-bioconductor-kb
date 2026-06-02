#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: crisprScore
// Provides R wrappers of several on-target and off-target scoring methods for CRISPR guide RNAs (gRNAs
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/crisprScore/inst/doc/crisprScore.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("crisprScore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprscore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crisprscore:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crisprscore:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprscore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprscore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprscore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(crisprScore)
    library(jsonlite)


    # --- Warnings=false [] ---
    # Key functions: crisprscore
    library(crisprScore)

    ## -----------------------------------------------------------------------------
    data(scoringMethodsInfo)
    print(scoringMethodsInfo)

    # --- Eval=true [] ---
    # Key functions: getRuleSet1Scores
    flank5 <- "ACCT" #4bp
    spacer <- "ATCGATGCTGATGCTAGATA" #20bp
    pam    <- "AGG" #3bp 
    flank3 <- "TTG" #3bp
    input  <- paste0(flank5, spacer, pam, flank3) 
    results <- getRuleSet1Scores(input)

    # --- Eval=true [] ---
    # Key functions: getCRISPRscanScores
    flank5 <- "ACCTAA" #6bp
    spacer <- "ATCGATGCTGATGCTAGATA" #20bp
    pam    <- "AGG" #3bp 
    flank3 <- "TTGAAT" #6bp
    input  <- paste0(flank5, spacer, pam, flank3) 
    results <- getCRISPRscanScores(input)

    # --- Eval=true [] ---
    # Key functions: getCRISPRaterScores
    spacer <- "ATCGATGCTGATGCTAGATA" #20bp
    results <- getCRISPRaterScores(spacer)

    # --- Eval=true [] ---
    # Key functions: crisprscore
    head(tssExampleCrispri)

    # --- Eval=true [] ---
    # Key functions: crisprscore
    head(sgrnaExampleCrispri)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crisprscore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crisprscore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crisprscore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRSCORE:", paste0("    crisprscore: ", packageVersion("crisprScore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprscore_results.csv
    touch ${prefix}_crisprscore_output.rds
    echo "BIOC_CRISPRSCORE:" > versions.yml
    echo "    crisprscore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRSCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRSCORE(ch_input)

    emit:
    results  = BIOC_CRISPRSCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRSCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRSCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRSCORE.out.versions  // channel: path(versions.yml)
}
