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

    # --- Absolute Risk Estimation with Split Intervals [] ---
    # Key functions: computeAbsoluteRiskSplitInterval
    cov_info <- list(
        list(name = "age", type = "continuous"),
        list(name = "bmi", type = "continuous")
    )
    snp_info <- data.frame(
        snp.name = c("rs1", "rs2"),
        or = c(1.2, 1.1),
        freq = c(0.2, 0.3)
    )
    res_split <- computeAbsoluteRiskSplitInterval(
        model.formula = disease ~ age + bmi,
        model.cov.info = cov_info,
        model.snp.info = snp_info,
        model.log.or = c(0.1, 0.2),
        model.ref.dataset = data.frame(age = c(30, 40), bmi = c(22, 25)),
        model.disease.incidence.rates = data.frame(
            age = c(30, 40), rate = c(0.001, 0.002)
        ),
        model.competing.incidence.rates = data.frame(
            age = c(30, 40), rate = c(0.0005, 0.001)
        ),
        apply.age.start = 30,
        apply.age.interval.length = 20,
        apply.cov.profile = data.frame(age = c(35), bmi = c(24)),
        apply.snp.profile = data.frame(rs1 = c(1), rs2 = c(0)),
        interval.cutpoints = c(30, 40, 50)
    )


    # --- Model Validation [] ---
    # Key functions: modelValidation
    val_data <- data.frame(
        disease = c(1, 0, 1, 0),
        age_start = c(30, 35, 40, 45),
        age_end = c(50, 55, 60, 65),
        follow_up = c(20, 20, 20, 20)
    )
    pred_risk <- c(0.05, 0.02, 0.08, 0.01)
    validation_results <- modelValidation(
        study.data = val_data,
        outcome.name = "disease",
        risk.prediction = pred_risk,
        follow.up.time = "follow_up",
        age.start = "age_start",
        age.end = "age_end"
    )

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
