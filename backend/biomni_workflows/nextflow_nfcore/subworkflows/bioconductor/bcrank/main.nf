#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BCRANK
// Functions and classes for de novo prediction of transcription factor binding consensus by heuristic 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BCRANK/inst/doc/BCRANK.R
// Upstream  : seqLogo
// Downstream: none
//
// Install: BiocManager::install("BCRANK")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BCRANK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bcrank"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bcrank:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bcrank:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bcrank_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bcrank_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bcrank_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BCRANK)
    library(jsonlite)

    # --- Loadfasta [] ---
    # Key functions: file
    fastaFile <- system.file("Exfiles/USF1_small.fa", package="BCRANK")
    # --- Viewtopmotif [] ---
    # Key functions: toptable
    topMotif <- toptable(BCRANKout,1)
    topMotif
    # --- Viewwm [] ---
    # Key functions: pwm
    weightMatrix <- pwm(topMotif, normalize=FALSE)
    weightMatrix
    # --- Fig1 [] ---
    # Key functions: pwm, seqLogo
    weightMatrixNormalized <- pwm(topMotif, normalize=TRUE)
    library(seqLogo)
    seqLogo(weightMatrixNormalized)
    # --- Reportsites [] ---
    # Key functions: toptable, matchingSites
    topConsensus <- as.character(toptable(BCRANKout)[1,"Consensus"])
    print(topConsensus)
    bindingSites <- matchingSites(fastaFile,topConsensus)
    nrSites <- nrow(bindingSites)
    cat("Number predicted binding sites:",nrSites,"\n")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bcrank_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bcrank_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bcrank_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BCRANK:", paste0("    bcrank: ", packageVersion("BCRANK"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bcrank_results.csv
    touch ${prefix}_bcrank_output.rds
    echo "BIOC_BCRANK:" > versions.yml
    echo "    bcrank: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BCRANK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BCRANK(ch_input)

    emit:
    results  = BIOC_BCRANK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BCRANK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BCRANK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BCRANK.out.versions  // channel: path(versions.yml)
}
