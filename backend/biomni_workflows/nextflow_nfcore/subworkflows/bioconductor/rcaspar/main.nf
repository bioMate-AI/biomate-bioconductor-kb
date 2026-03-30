#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RCASPAR
// The package is the R-version of the C-based software \bold{CASPAR} (Kaderali,2006: \url{http://bioin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RCASPAR/inst/doc/RCASPAR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RCASPAR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCASPAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcaspar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcaspar:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcaspar:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcaspar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcaspar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcaspar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(STpredictor_BLH)
    library(jsonlite)

    # --- Pltgamma [] ---
    # Key functions: pltgamma
    pltgamma(a=1.558,b=0.179)
    # --- Stpredictor Blh [] ---
    # Key functions: STpredictor_BLH
    data(Bergamaschi)
    data(survData)
    result <- STpredictor_BLH(geDataS=Bergamaschi[1:27, 1:2], survDataS=survData[1:27, 9:10], geDataT=Bergamaschi[28:82, 1:2],
    survDataT=survData[28:82, 9:10], q = 1, s = 1, a = 1.558, b = 0.179, cut.off=15, groups = 3, method = "CG", noprior = 1,
    extras = list(reltol=1))
    # --- Kmplt Svrl [] ---
    # Key functions: kmplt_svrl
    kmplt_svrl(long=result$long_survivors, short=result$short_survivors,title="KM plot of long and short survivors")
    # --- Survivaurc [] ---
    # Key functions: survivAURC
    survivAURC(Stime=result$predicted_STs$True_STs,status=result$predicted_STs$censored, marker=result$predicted_STs$Predicted_STs, time.max=20)
    # --- Logrank [] ---
    # Key functions: logrnk
    logrnk(dataL=result$long_survivors, dataS=result$short_survivors)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcaspar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcaspar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcaspar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCASPAR:", paste0("    rcaspar: ", packageVersion("RCASPAR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcaspar_results.csv
    touch ${prefix}_rcaspar_output.rds
    echo "BIOC_RCASPAR:" > versions.yml
    echo "    rcaspar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCASPAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCASPAR(ch_input)

    emit:
    results  = BIOC_RCASPAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCASPAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCASPAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCASPAR.out.versions  // channel: path(versions.yml)
}
