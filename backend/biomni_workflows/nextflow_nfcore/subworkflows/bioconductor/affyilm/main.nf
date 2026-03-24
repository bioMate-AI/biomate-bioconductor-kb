#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affyILM
// affyILM is a preprocessing tool which estimates gene expression levels for Affymetrix Gene Chips. In
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affyILM/inst/doc/affyILM.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("affyILM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYILM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affyilm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affyilm:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affyilm:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affyilm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affyilm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affyilm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(affyILM)
    library(jsonlite)

    # --- Ilm [] ---
    # Key functions: ilm
    result <- ilm(file1);
    # --- Getintens [] ---
    # Key functions: getIntens
    getIntens(result,"AFFX-r2-Ec-bioD-5_at")
    # --- Plotintens [] ---
    # Key functions: plotIntens
    plotIntens(result,"AFFX-r2-Ec-bioD-5_at","HG-Focus-1-121502.CEL")
    # --- Getintens [] ---
    # Key functions: getIntens
    getIntens(result2files,"AFFX-r2-Ec-bioD-5_at")
    # --- Getprobeconcs [] ---
    # Key functions: getProbeConcs
    getProbeConcs(result2files,"AFFX-r2-Ec-bioD-5_at")
    # --- Plotilm [] ---
    # Key functions: plotILM
    pILM<-plotILM(result2files,"AFFX-r2-Ec-bioD-5_at","HG-Focus-1-121502.CEL")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affyilm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affyilm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affyilm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYILM:", paste0("    affyilm: ", packageVersion("affyILM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affyilm_results.csv
    touch ${prefix}_affyilm_output.rds
    echo "BIOC_AFFYILM:" > versions.yml
    echo "    affyilm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYILM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFYILM(ch_input)

    emit:
    results  = BIOC_AFFYILM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYILM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYILM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYILM.out.versions  // channel: path(versions.yml)
}
