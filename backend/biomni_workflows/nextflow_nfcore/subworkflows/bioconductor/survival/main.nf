#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: survival (CRAN 3.5-8)
// Kaplan-Meier survival curves, log-rank tests, and Cox
// proportional hazards regression for time-to-event analysis.
//
// Source : https://cran.r-project.org/package=survival
// Upstream  : broom, dplyr
// Downstream: survminer, ggsurvfit, rms
//
// Install: install.packages("survival")
// Reference: Therneau TM (2024). A Package for Survival Analysis in R.
// ============================================================

nextflow.enable.dsl = 2

// [Survival Analysis]
process CRAN_SURVIVAL_KAPLANMEIER {
    tag "${meta.id}"
    label 'process_low'

    conda "r-survival r-broom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/r-survival:3.5_8--r44_0' :
        'quay.io/biocontainers/r-survival:3.5_8--r44_0'}"

    input:
    tuple val(meta), path(clinical_csv)
    val time_col
    val event_col
    val group_col

    output:
    tuple val(meta), path("${meta.id}_km_fit.rds")         , emit: km_fit
    tuple val(meta), path("${meta.id}_km_summary.csv")     , emit: km_summary
    tuple val(meta), path("${meta.id}_logrank_pvalue.txt") , emit: logrank_pval
    path "versions.yml"                                    , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(survival)

    data <- read.csv("${clinical_csv}", stringsAsFactors=FALSE)

    # Build survival object
    surv_obj <- Surv(time  = data[["${time_col}"]],
                     event = as.integer(data[["${event_col}"]] == 1))

    # Kaplan-Meier fit
    km_formula <- as.formula(paste0("surv_obj ~ data[['", "${group_col}", "']]"))
    km_fit     <- survfit(km_formula)
    saveRDS(km_fit, "${prefix}_km_fit.rds")

    # Summary table
    km_tbl <- summary(km_fit)\$table
    write.csv(as.data.frame(km_tbl), "${prefix}_km_summary.csv")

    # Log-rank test p-value
    lr_test <- survdiff(km_formula)
    pval    <- 1 - pchisq(lr_test\$chisq, df = length(lr_test\$n) - 1)
    writeLines(as.character(pval), "${prefix}_logrank_pvalue.txt")

    # versions.yml
    writeLines(
        c("CRAN_SURVIVAL_KAPLANMEIER:",
          paste0("    survival: ", packageVersion("survival"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_km_fit.rds
    touch ${prefix}_km_summary.csv
    echo "0.05" > ${prefix}_logrank_pvalue.txt
    echo "CRAN_SURVIVAL_KAPLANMEIER:" > versions.yml
    echo "    survival: 0.0.0" >> versions.yml
    """
}

// [Survival Analysis]
process CRAN_SURVIVAL_COX {
    tag "${meta.id}"
    label 'process_low'

    conda "r-survival r-broom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/r-survival:3.5_8--r44_0' :
        'quay.io/biocontainers/r-survival:3.5_8--r44_0'}"

    input:
    tuple val(meta), path(clinical_csv)
    val time_col
    val event_col
    val covariates     // comma-separated column names e.g. "age,stage,treatment"

    output:
    tuple val(meta), path("${meta.id}_cox_results.csv") , emit: cox_results
    tuple val(meta), path("${meta.id}_cox_model.rds")   , emit: cox_model
    path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(survival)
    suppressPackageStartupMessages(library(broom))

    data     <- read.csv("${clinical_csv}", stringsAsFactors=FALSE)
    cov_list <- trimws(strsplit("${covariates}", ",")[[1]])

    # Build Cox formula
    cox_formula <- as.formula(paste0(
        "Surv(", "${time_col}", ", ", "${event_col}", " == 1) ~ ",
        paste(cov_list, collapse = " + ")
    ))

    cox_fit <- coxph(cox_formula, data = data)
    saveRDS(cox_fit, "${prefix}_cox_model.rds")

    # Export hazard ratios with 95% CI
    results <- broom::tidy(cox_fit, exponentiate = TRUE, conf.int = TRUE)
    write.csv(results, "${prefix}_cox_results.csv", row.names = FALSE)

    # versions.yml
    writeLines(
        c("CRAN_SURVIVAL_COX:",
          paste0("    survival: ", packageVersion("survival")),
          paste0("    broom: ",    packageVersion("broom"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cox_model.rds
    echo "term,estimate,std.error,statistic,p.value,conf.low,conf.high" > ${prefix}_cox_results.csv
    echo "CRAN_SURVIVAL_COX:" > versions.yml
    echo "    survival: 0.0.0" >> versions.yml
    echo "    broom: 0.0.0" >> versions.yml
    """
}

// ─── Standalone entry workflow ───────────────────────────────────────────────

workflow {
    ch_input = Channel.of(
        [[id: 'test'],
         file(params.clinical_csv ?: 'NO_FILE')]
    )

    SURVIVAL_ANALYSIS(
        ch_input,
        params.time_col   ?: 'time',
        params.event_col  ?: 'event',
        params.group_col  ?: 'treatment',
        params.covariates ?: 'age'
    )

    SURVIVAL_ANALYSIS.out.km_fit.view { meta, f ->
        "KM fit written: ${f}"
    }
    SURVIVAL_ANALYSIS.out.cox_results.view { meta, f ->
        "Cox results written: ${f}"
    }
}

workflow SURVIVAL_ANALYSIS {
    take:
    clinical_data  // channel: [ val(meta), path(clinical_csv) ]
    time_col       // val: column name for follow-up time
    event_col      // val: column name for event indicator (0=censored, 1=event)
    group_col      // val: column name for grouping variable (KM)
    covariates     // val: comma-separated covariates for Cox model

    main:
    ch_versions = Channel.empty()

    CRAN_SURVIVAL_KAPLANMEIER(clinical_data, time_col, event_col, group_col)
    ch_versions = ch_versions.mix(CRAN_SURVIVAL_KAPLANMEIER.out.versions)

    CRAN_SURVIVAL_COX(clinical_data, time_col, event_col, covariates)
    ch_versions = ch_versions.mix(CRAN_SURVIVAL_COX.out.versions)

    emit:
    km_fit       = CRAN_SURVIVAL_KAPLANMEIER.out.km_fit      // [ meta, km_fit.rds ]
    km_summary   = CRAN_SURVIVAL_KAPLANMEIER.out.km_summary  // [ meta, km_summary.csv ]
    logrank_pval = CRAN_SURVIVAL_KAPLANMEIER.out.logrank_pval // [ meta, logrank_pvalue.txt ]
    cox_results  = CRAN_SURVIVAL_COX.out.cox_results          // [ meta, cox_results.csv ]
    cox_model    = CRAN_SURVIVAL_COX.out.cox_model            // [ meta, cox_model.rds ]
    versions     = ch_versions
}
