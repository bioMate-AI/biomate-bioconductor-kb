#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iCARE
// An R package to build, validate and apply absolute risk models
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iCARE/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iCARE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICARE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-icare"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-icare:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-icare:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_icare_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_icare_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_icare_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iCARE)
    library(jsonlite)

    # --- Load Data [] ---
    # Key functions: data
    data("bc_data", package="iCARE")
    # --- Model 1A [] ---
    # Key functions: computeAbsoluteRisk

    # --- Summary 1A [] ---
    # Key functions: density
    summary(res_snps_miss$risk)
    summary(res_snps_miss$refs.risk)
    plot(density(res_snps_miss$risk), lwd=2,
      main="SNP-only Risk Stratification: Ages 50-80",
      xlab="Absolute Risk of Breast Cancer")
    # --- Model 1B [] ---
    # Key functions: computeAbsoluteRisk

    # --- Plot 1B [] ---
    # Key functions: density
    plot(density(res_snps_dat$refs.risk), lwd=2,
       main="Referent SNP-only Risk Distribution: Ages 50-80",
       xlab="Absolute Risk of Breast Cancer")
    abline(v=res_snps_dat$risk, col="red")
    legend("topright", legend="New Profiles", col="red", lwd=1)
    # --- Fit 2 [] ---
    # Key functions: computeAbsoluteRisk


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_icare_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_icare_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_icare_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ICARE:", paste0("    icare: ", packageVersion("iCARE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_icare_results.csv
    touch ${prefix}_icare_output.rds
    echo "BIOC_ICARE:" > versions.yml
    echo "    icare: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ICARE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ICARE(ch_input)

    emit:
    results  = BIOC_ICARE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ICARE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ICARE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ICARE.out.versions  // channel: path(versions.yml)
}
